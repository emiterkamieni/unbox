import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        let host = NSHostingController(rootView: ContentView().environmentObject(model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        Publishers.CombineLatest3(model.$items, model.$isApplying, model.$isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] items, isApplying, _ in self?.updateStatusItem(count: items.count, busy: isApplying) }
            .store(in: &subscriptions)

        model.$refreshMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] minutes in self?.scheduleRefresh(every: minutes) }
            .store(in: &subscriptions)

        model.refresh(force: true)

        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.togglePopover() }
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
        let symbol = busy ? "arrow.clockwise.icloud" : "icloud.and.arrow.down"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Debox")
        image?.isTemplate = true
        button.image = image
        button.title = count > 0 ? " \(count)" : ""
        button.toolTip = count > 0 ? "Box offline: \(Plural.items(count))" : "Box offline: brak"
    }

    private func scheduleRefresh(every minutes: Int) {
        refreshTimer?.invalidate()
        let model = self.model
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, minutes) * 60), repeats: true) { _ in
            Task { @MainActor in model.refresh() }
        }
    }
}
