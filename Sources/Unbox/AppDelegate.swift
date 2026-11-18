import AppKit
import UnboxKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let updates = UpdateController()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        Demo.applyAppearance()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageOnly

        let host = NSHostingController(rootView: ContentView().environmentObject(model).environmentObject(updates))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.appearance // nil unless the demo asks for light or dark

        Publishers.CombineLatest3(model.$items, model.$isApplying, model.$language)
            .receive(on: RunLoop.main)
            .sink { [weak self] items, isApplying, _ in self?.updateStatusItem(count: items.count, busy: isApplying) }
            .store(in: &subscriptions)

        model.$refreshMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] minutes in self?.scheduleRefresh(every: minutes) }
            .store(in: &subscriptions)

        model.refresh(force: true)
        if !Demo.isEnabled { updates.start() }

        if Demo.snapshotFolder != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.takeSnapshots() }
        } else if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.togglePopover() }
        }
    }

    /// `--demo --snapshot <folder>`: saves the list and the settings, then quits.
    private func takeSnapshots() {
        togglePopover()
        guard let window = popover.contentViewController?.view.window else { exit(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Demo.capture(window, named: "list")
            self.model.showingSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Demo.capture(window, named: "settings")
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            let window = popover.contentViewController?.view.window
            window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { window?.makeFirstResponder(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.popoverDidClose()
    }

    private func updateStatusItem(count: Int, busy: Bool) {
        guard let button = statusItem.button else { return }
        button.image = Brand.symbol
        button.appearsDisabled = busy
        if busy {
            button.toolTip = L10n.text("unbox: changing offline settings…", "unbox: zmieniam ustawienia offline…")
        } else if count > 0 {
            button.toolTip = L10n.format("unbox – offline: %@", "unbox – offline: %@", Plural.items(count))
        } else {
            button.toolTip = L10n.text("unbox – nothing is offline", "unbox – nic nie jest offline")
        }
    }

    private func scheduleRefresh(every minutes: Int) {
        refreshTimer?.invalidate()
        let model = self.model
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, minutes) * 60), repeats: true) { _ in
            Task { @MainActor in model.refresh() }
        }
    }
}
