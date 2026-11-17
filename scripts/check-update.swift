// End-to-end update check against the published GitHub release.
//
// Copies build/unbox.app to a temporary folder, marks the copy as version 0.9.0 (build 0) and lets
// Sparkle update it without any UI: find the update in the live appcast, download it, verify the
// EdDSA signature, then replace the copy. The installed app is not touched.
//
//   scripts/check-update.sh
import AppKit
import Sparkle

final class HeadlessDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { print("checking feed…") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("found \(appcastItem.displayVersionString) (build \(appcastItem.versionString)), installing")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("FAIL: no update found – \(error.localizedDescription)")
        exit(1)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("FAIL: \(error.localizedDescription) \((error as NSError).userInfo)")
        exit(1)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { print("downloading…") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("verifying signature and extracting…") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("verified, installing")
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // Sparkle's installer replaces the bundle once this (host) process has exited.
        print("installer running")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

final class Delegate: NSObject, SPUUpdaterDelegate {
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { false }
}

let target = URL(fileURLWithPath: CommandLine.arguments[1])
guard let host = Bundle(url: target) else { print("FAIL: no bundle at \(target.path)"); exit(1) }
let driver = HeadlessDriver()
let delegate = Delegate()
let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: delegate)
do { try updater.start() } catch { print("FAIL: \(error)"); exit(1) }
updater.checkForUpdates()
DispatchQueue.main.asyncAfter(deadline: .now() + 180) { print("FAIL: timed out"); exit(1) }
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
