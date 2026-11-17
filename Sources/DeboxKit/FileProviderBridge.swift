import Foundation
import ObjectiveC

/// Snapshot of what macOS File Provider knows about an item.
public struct FileProviderItemInfo: @unchecked Sendable {
    public let itemIdentifier: String
    public let providerDomainID: String
    public let isFolder: Bool
    public let isDownloaded: Bool
    public let isUploaded: Bool
    let userInfo: [String: Any]

    /// Box offers "Make Available Online Only" only for items that are marked offline.
    public var isMarkedOffline: Bool { flag("UnmarkForOffline") }
    public var canBeMarkedOffline: Bool { flag("MarkForOffline") }

    /// "com.box.desktop.boxfileprovider" for Box Drive.
    public var providerID: String {
        String(providerDomainID.split(separator: "/", maxSplits: 1).first ?? "")
    }

    private func flag(_ key: String) -> Bool {
        (userInfo[key] as? NSNumber)?.boolValue ?? false
    }
}

public enum BoxAction: String, Sendable {
    case markForOffline = "MarkForOffline"
    case unmarkForOffline = "UnmarkForOffline"
}

/// Talks to macOS File Provider the same way Finder does.
///
/// Box exposes "Make Available Offline" / "Make Available Online Only" as custom File Provider
/// actions. There is no public API for triggering another app's actions, so this uses the
/// FileProvider framework's internal classes. Every selector is checked before use, so a future
/// macOS change results in `fileProviderUnavailable` instead of a crash.
public final class FileProviderBridge: @unchecked Sendable {
    public static let shared = FileProviderBridge()

    private typealias FetchFn = @convention(c) (NSObject, Selector, NSURL, @escaping @convention(block) (NSObject?, NSError?) -> Void) -> Void
    private typealias InitActionFn = @convention(c) (NSObject, Selector, NSString, NSString, NSArray) -> NSObject?

    private let manager: NSObject?
    private let actionClass: NSObject.Type?
    private let fetchSelector = NSSelectorFromString("fetchItemForURL:completionHandler:")
    private let scheduleSelector = NSSelectorFromString("scheduleAction:")
    private let initActionSelector = NSSelectorFromString("initWithActionIdentifier:providerDomainID:itemIdentifiers:")

    private init() {
        _ = dlopen("/System/Library/Frameworks/FileProvider.framework/FileProvider", RTLD_NOW)
        if let managerClass = NSClassFromString("FPItemManager") as? NSObject.Type,
           managerClass.responds(to: NSSelectorFromString("defaultManager")),
           let instance = managerClass.perform(NSSelectorFromString("defaultManager"))?.takeUnretainedValue() as? NSObject {
            manager = instance
        } else {
            manager = nil
        }
        actionClass = NSClassFromString("FPVendorDefinedActionOperation") as? NSObject.Type
    }

    public var canReadItems: Bool {
        manager?.responds(to: fetchSelector) ?? false
    }

    public var canPerformActions: Bool {
        guard let manager, let actionClass else { return false }
        return manager.responds(to: scheduleSelector)
            && actionClass.instancesRespond(to: initActionSelector)
            && actionClass.instancesRespond(to: NSSelectorFromString("setFinishedBlock:"))
    }

    public func item(at url: URL) async throws -> FileProviderItemInfo {
        guard let manager, canReadItems else { throw DeboxError.fileProviderUnavailable }
        let fetch = unsafeBitCast(manager.method(for: fetchSelector), to: FetchFn.self)
        let raw: NSObject = try await withCheckedThrowingContinuation { continuation in
            fetch(manager, fetchSelector, url as NSURL) { item, error in
                if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: error ?? DeboxError.itemNotInBox(url.path))
                }
            }
        }
        return try Self.info(from: raw, url: url)
    }

    public func perform(_ action: BoxAction, on item: FileProviderItemInfo, timeout: TimeInterval = 120) async throws {
        guard let manager, let actionClass, canPerformActions else { throw DeboxError.fileProviderUnavailable }

        let identifier = "\(item.providerID).\(action.rawValue)"
        guard let allocated = actionClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else {
            throw DeboxError.fileProviderUnavailable
        }
        let initAction = unsafeBitCast(allocated.method(for: initActionSelector), to: InitActionFn.self)
        guard let operation = initAction(allocated, initActionSelector, identifier as NSString,
                                         item.providerDomainID as NSString, [item.itemIdentifier] as NSArray) else {
            throw DeboxError.fileProviderUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            let finished: @convention(block) (AnyObject?, NSError?) -> Void = { _, error in
                if let error {
                    once.resume(throwing: DeboxError.actionFailed(error.localizedDescription))
                } else {
                    once.resume()
                }
            }
            operation.setValue(finished, forKey: "finishedBlock")
            manager.perform(scheduleSelector, with: operation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(throwing: DeboxError.actionTimedOut)
            }
        }
    }

    /// Removes the local copy of an item (Finder's "Remove Download"). Folders are evicted recursively.
    /// The system refuses to evict files with changes that were not uploaded yet.
    public func evict(_ url: URL) throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }

    private static func info(from item: NSObject, url: URL) throws -> FileProviderItemInfo {
        func value(_ key: String) -> Any? {
            item.responds(to: NSSelectorFromString(key)) ? item.value(forKey: key) : nil
        }
        func bool(_ key: String) -> Bool { (value(key) as? NSNumber)?.boolValue ?? false }

        guard let identifier = value("itemIdentifier") as? String,
              let domain = value("providerDomainID") as? String else {
            throw DeboxError.itemNotInBox(url.path)
        }
        return FileProviderItemInfo(
            itemIdentifier: identifier,
            providerDomainID: domain,
            isFolder: bool("isFolder"),
            isDownloaded: bool("isDownloaded"),
            isUploaded: bool("isUploaded"),
            userInfo: value("userInfo") as? [String: Any] ?? [:]
        )
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}
