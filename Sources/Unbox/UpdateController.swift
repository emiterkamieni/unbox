import AppKit
import Sparkle
import UnboxKit
import UserNotifications

/// Update checks and installation.
///
/// Sparkle downloads the update, verifies its EdDSA signature and replaces the app. unbox only
/// schedules a silent check every 24 hours and, when a new version is found, posts a notification
/// and shows a notice in the popover. Installing always goes through Sparkle's own window.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var availableVersion: String?
    @Published var notifyAboutUpdates: Bool {
        didSet {
            defaults.set(notifyAboutUpdates, forKey: Keys.notify)
            if notifyAboutUpdates { checkIfDue() } else { removeNotification() }
        }
    }

    private let defaults = UserDefaults.standard
    private var controller: SPUStandardUpdaterController?
    private var timer: Timer?
    private var silentCheckInProgress = false

    private enum Keys {
        static let notify = "notifyAboutUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let notifiedVersion = "notifiedUpdateVersion"
    }
    nonisolated private static let notificationID = "unbox.update"

    override init() {
        notifyAboutUpdates = UserDefaults.standard.object(forKey: Keys.notify) as? Bool ?? true
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        UNUserNotificationCenter.current().delegate = self
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func start() {
        checkIfDue()
    }

    /// Opens Sparkle's window: it shows the release notes and installs on request.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    private func checkIfDue() {
        timer?.invalidate()
        guard notifyAboutUpdates, let updater = controller?.updater else { return }
        let last = defaults.object(forKey: Keys.lastCheck) as? Date ?? .distantPast
        let remaining = Self.checkInterval - Date().timeIntervalSince(last)
        if remaining <= 0 || last > Date() {
            if !updater.sessionInProgress {
                defaults.set(Date(), forKey: Keys.lastCheck)
                silentCheckInProgress = true
                updater.checkForUpdateInformation()
            }
            schedule(after: Self.checkInterval)
        } else {
            schedule(after: remaining)
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: max(60, delay), repeats: false) { [unowned self] _ in
            Task { @MainActor in self.checkIfDue() }
        }
    }

    private func found(version: String) {
        availableVersion = version
        guard silentCheckInProgress, notifyAboutUpdates,
              defaults.string(forKey: Keys.notifiedVersion) != version else { return }
        postNotification(version: version)
    }

    private func postNotification(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.format("unbox %@", "unbox %@", version)
            content.body = L10n.text("Update available.", "Dostępna aktualizacja.")
            center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)) { error in
                guard error == nil else { return }
                Task { @MainActor in self.defaults.set(version, forKey: Keys.notifiedVersion) }
            }
        }
    }

    private func removeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.found(version: version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in self.silentCheckInProgress = false }
    }
}

extension UpdateController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let isUpdate = response.notification.request.identifier == Self.notificationID
        Task { @MainActor in
            if isUpdate { self.checkForUpdates() }
            completionHandler()
        }
    }
}
