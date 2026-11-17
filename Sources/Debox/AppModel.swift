import AppKit
import DeboxKit
import Network
import SwiftUI

struct ItemGroup: Identifiable {
    let name: String
    let items: [OfflineItem]
    var id: String { name }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case name, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Nazwa (A–Z)"
        case .size: return "Rozmiar (największe)"
        }
    }
}

enum RowActivity: Equatable {
    case waiting, working, done, failed
}

struct Banner: Equatable {
    enum Kind { case success, warning, failure }
    let kind: Kind
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [OfflineItem] = []
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var activity: [String: RowActivity] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var loadError: String?
    @Published private(set) var isBoxRunning = true
    @Published private(set) var isOnline = true
    @Published var banner: Banner?
    @Published var markedOnlineOnly: Set<String> = []
    @Published var showingSettings = false

    @Published var freeSpace: Bool {
        didSet { UserDefaults.standard.set(freeSpace, forKey: Keys.freeSpace) }
    }
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }
    @Published var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published private(set) var launchAtLoginNeedsApproval = LoginItem.needsApproval
    @Published private(set) var launchAtLoginError: String?

    private let service: OfflineService?
    private let pathMonitor = NWPathMonitor()

    private enum Keys {
        static let freeSpace = "freeSpaceAfterUnmark"
        static let refreshMinutes = "refreshMinutes"
        static let sortOrder = "sortOrder"
    }

    init() {
        UserDefaults.standard.register(defaults: [Keys.freeSpace: true, Keys.refreshMinutes: 5])
        freeSpace = UserDefaults.standard.bool(forKey: Keys.freeSpace)
        refreshMinutes = UserDefaults.standard.integer(forKey: Keys.refreshMinutes)
        sortOrder = UserDefaults.standard.string(forKey: Keys.sortOrder).flatMap(SortOrder.init(rawValue:)) ?? .name

        do {
            service = try OfflineService()
        } catch {
            service = nil
            loadError = error.localizedDescription
        }

        let model = self
        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in model.isOnline = online }
        }
        pathMonitor.start(queue: DispatchQueue(label: "debox.network"))
    }

    // MARK: - Derived state

    var canChangeOfflineState: Bool { service?.canChangeOfflineState ?? false }

    /// Groups and the items inside them follow the same order: alphabetical, or largest first.
    /// While sizes are still being measured, size sorting falls back to names.
    var groups: [ItemGroup] {
        let groups = Dictionary(grouping: items, by: \.group).map { name, members in
            ItemGroup(name: name, items: members.sorted {
                isOrdered($0.name, sizes[$0.id], before: $1.name, sizes[$1.id], tieBreak: ($0.relativePath, $1.relativePath))
            })
        }
        return groups.sorted { isOrdered($0.name, total(of: $0.items), before: $1.name, total(of: $1.items)) }
    }

    private func isOrdered(_ lhsName: String, _ lhsSize: Int64?, before rhsName: String, _ rhsSize: Int64?,
                           tieBreak: (String, String)? = nil) -> Bool {
        if sortOrder == .size, let lhsSize, let rhsSize, lhsSize != rhsSize {
            return lhsSize > rhsSize
        }
        let byName = lhsName.localizedStandardCompare(rhsName)
        if byName != .orderedSame { return byName == .orderedAscending }
        guard let tieBreak else { return false }
        return tieBreak.0.localizedStandardCompare(tieBreak.1) == .orderedAscending
    }

    var totalSize: Int64? { total(of: items) }
    var selectedSize: Int64? { total(of: items.filter { markedOnlineOnly.contains($0.id) }) }

    func total(of items: [OfflineItem]) -> Int64? {
        var sum: Int64 = 0
        for item in items {
            guard let size = sizes[item.id] else { return nil }
            sum += size
        }
        return sum
    }

    func keepsOffline(_ item: OfflineItem) -> Binding<Bool> {
        Binding(
            get: { !self.markedOnlineOnly.contains(item.id) },
            set: { keep in
                guard !self.isApplying else { return }
                if keep { self.markedOnlineOnly.remove(item.id) } else { self.markedOnlineOnly.insert(item.id) }
                self.banner = nil
            }
        )
    }

    // MARK: - Actions

    func refresh(force: Bool = false) {
        isBoxRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.box.desktop").isEmpty
        refreshLoginItemState()
        guard let service, !isLoading, !isApplying else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 5 { return }

        isLoading = true
        Task {
            do {
                let found = try await service.scan()
                items = found
                markedOnlineOnly.formIntersection(Set(found.map(\.id)))
                loadError = nil
                lastRefresh = Date()
                isLoading = false
                sizes = await Self.measure(found)
            } catch {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    func apply() {
        guard let service, !isApplying else { return }
        let targets = items.filter { markedOnlineOnly.contains($0.id) }
        guard !targets.isEmpty else { return }

        let freeSpace = self.freeSpace
        isApplying = true
        banner = nil
        activity = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, .waiting) })

        Task {
            var freed: Int64 = 0
            var keptLocally = 0
            var failures: [String] = []
            for item in targets {
                activity[item.id] = .working
                do {
                    let outcome = try await service.makeOnlineOnly(item, freeSpace: freeSpace)
                    freed += outcome.freedBytes
                    keptLocally += outcome.filesKeptLocally
                    activity[item.id] = .done
                } catch {
                    failures.append("\(item.name): \(error.localizedDescription)")
                    activity[item.id] = .failed
                }
            }

            banner = Self.summary(done: targets.count - failures.count, freed: freed, freeSpace: freeSpace,
                                  keptLocally: keptLocally, failures: failures)
            isApplying = false
            activity = [:]
            markedOnlineOnly.removeAll()
            refresh(force: true)
        }
    }

    func cancelSelection() {
        markedOnlineOnly.removeAll()
    }

    func popoverDidClose() {
        if !isApplying, banner?.kind == .success { banner = nil }
    }

    func reveal(_ item: OfflineItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func launchBox() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.box.desktop") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            Task { @MainActor in self.refresh(force: true) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLoginItemState()
    }

    func openLoginItemsSettings() {
        LoginItem.openSystemSettings()
    }

    private func refreshLoginItemState() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        launchAtLoginNeedsApproval = LoginItem.needsApproval
    }

    // MARK: - Helpers

    private static func measure(_ items: [OfflineItem]) async -> [String: Int64] {
        await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: items.map { ($0.id, DiskUsage.allocatedSize(of: $0.url)) })
        }.value
    }

    private static func summary(done: Int, freed: Int64, freeSpace: Bool, keptLocally: Int, failures: [String]) -> Banner {
        var parts: [String] = []
        if done > 0 {
            parts.append("Tylko online: \(Plural.items(done)).")
            if freeSpace { parts.append("Zwolniono \(Format.bytes(freed)).") }
        }
        if freeSpace && keptLocally > 0 {
            let verb = Plural.form(keptLocally, "został", "zostały", "zostało")
            parts.append("\(Plural.files(keptLocally)) \(verb) na dysku (niewysłane zmiany lub otwarte pliki).")
        }
        if !failures.isEmpty {
            parts.append(failures.joined(separator: "\n"))
            return Banner(kind: done > 0 ? .warning : .failure, message: parts.joined(separator: " "))
        }
        return Banner(kind: keptLocally > 0 && freeSpace ? .warning : .success, message: parts.joined(separator: " "))
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

enum Plural {
    static func items(_ n: Int) -> String { "\(n) " + form(n, "element", "elementy", "elementów") }
    static func files(_ n: Int) -> String { "\(n) " + form(n, "plik", "pliki", "plików") }

    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let lastDigit = n % 10, lastTwo = n % 100
        return (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) ? few : many
    }
}
