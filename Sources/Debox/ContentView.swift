import AppKit
import DeboxKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            if model.showingSettings {
                SettingsView()
            } else {
                NoticesView()
                ItemListView()
                Divider()
                FooterView()
            }
        }
        .frame(width: 440)
        // macOS 26 popovers are very translucent; a calm base layer keeps the list readable
        // regardless of the windows behind it.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.showingSettings ? "Ustawienia" : "Box offline")
                    .font(.headline)
                if !model.showingSettings {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if !model.showingSettings && !model.items.isEmpty {
                SortMenu()
            }
            if !model.showingSettings {
                Button {
                    model.refresh(force: true)
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading || model.isApplying)
                .help("Odśwież")
            }
            Button {
                model.showingSettings.toggle()
            } label: {
                Image(systemName: model.showingSettings ? "xmark.circle.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(model.showingSettings ? "Zamknij ustawienia" : "Ustawienia")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        if model.items.isEmpty { return model.isLoading ? "Sprawdzanie…" : "Nic nie jest pobrane offline" }
        let size = model.totalSize.map { " · \(Format.bytes($0)) na dysku" } ?? ""
        return Plural.items(model.items.count) + size
    }
}

/// A plain borderless button (so it looks like its neighbours) that opens a native menu with a checkmark.
private struct SortMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(.borderless)
        .help("Sortuj według: \(model.sortOrder.title.lowercased())")
    }

    private func showMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Sortuj według", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for order in SortOrder.allCases {
            let target = MenuAction { model.sortOrder = order }
            let item = NSMenuItem(title: order.title, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = target
            item.representedObject = target // menu items hold their target weakly
            item.state = model.sortOrder == order ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

private struct NoticesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                NoticeRow(symbol: "exclamationmark.triangle.fill", tint: .red, text: error)
            }
            if !model.isBoxRunning {
                NoticeRow(symbol: "pause.circle.fill", tint: .orange,
                          text: "Box Drive nie działa. Uruchom go, aby zmieniać ustawienia offline.",
                          actionTitle: "Uruchom Box", action: { model.launchBox() })
            }
            if model.loadError == nil && !model.canChangeOfflineState {
                NoticeRow(symbol: "info.circle.fill", tint: .orange,
                          text: "macOS nie pozwala tu na automatyczne odznaczanie. Użyj „Pokaż w Finderze” → prawy przycisk → Make Available Online Only.")
            }
        }
    }
}

private struct NoticeRow: View {
    let symbol: String
    let tint: Color
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
    }
}

private struct ItemListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: model.isLoading ? "hourglass" : "checkmark.icloud")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(model.isLoading ? "Sprawdzanie plików offline…" : "Żaden folder ani plik nie jest oznaczony offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.groupSpacing) {
                    ForEach(model.groups) { group in
                        GroupSection(group: group)
                    }
                }
                .padding(Layout.listPadding)
                .animation(.easeInOut(duration: 0.2), value: model.sortOrder)
            }
            .frame(height: listHeight)
        }
    }

    private var listHeight: CGFloat {
        let groups = CGFloat(model.groups.count)
        let rows = CGFloat(model.items.count)
        let content = rows * Layout.rowHeight
            + (rows - groups) // dividers between rows
            + groups * (Layout.headerHeight + Layout.headerSpacing)
            + max(0, groups - 1) * Layout.groupSpacing
            + Layout.listPadding * 2
        return min(max(content, 120), 470)
    }
}

private enum Layout {
    static let rowHeight: CGFloat = 44
    static let headerHeight: CGFloat = 16
    static let headerSpacing: CGFloat = 6
    static let groupSpacing: CGFloat = 14
    static let listPadding: CGFloat = 12
    static let cardRadius: CGFloat = 9
    /// Divider inset so it starts under the item name, not under the checkbox.
    static let dividerInset: CGFloat = 60
}

private struct GroupSection: View {
    @EnvironmentObject private var model: AppModel
    let group: ItemGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let size = model.total(of: group.items) {
                    Text(Format.bytes(size))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(height: Layout.headerHeight)
            .padding(.horizontal, 4)

            let card = RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, Layout.dividerInset)
                    }
                    ItemRow(item: item)
                }
            }
            .background(card.fill(Color.primary.opacity(0.045)))
            .clipShape(card)
            .overlay(card.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: OfflineItem
    @State private var isHovered = false

    var body: some View {
        let keepOffline = model.keepsOffline(item)
        let isKept = keepOffline.wrappedValue
        HStack(spacing: 8) {
            Toggle("", isOn: keepOffline)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.isApplying || !model.canChangeOfflineState)
                .help(isKept ? "Odznacz, aby ustawić jako tylko online" : "Pozostaw offline")

            HStack(spacing: 8) {
                Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isKept ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(!isKept, color: .secondary)
                        .foregroundStyle(isKept ? .primary : .secondary)
                    if !item.intermediatePath.isEmpty {
                        Text(item.intermediatePath.joined(separator: " › "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !model.isApplying && model.canChangeOfflineState { keepOffline.wrappedValue.toggle() }
            }
            .help(item.relativePath)

            HStack(spacing: 8) {
                trailing(isKept: isKept)
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.rowHeight)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func trailing(isKept: Bool) -> some View {
        switch model.activity[item.id] {
        case .working:
            ProgressView().controlSize(.small)
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case nil:
            Text(model.sizes[item.id].map(Format.bytes) ?? "…")
                .font(.callout)
                .foregroundStyle(isKept ? Color.secondary : Color.orange)
                .monospacedDigit()
                .help(isKept ? "Miejsce zajmowane na dysku" : "Tyle miejsca się zwolni")
            // Shown only on hover so it takes no space otherwise; the size slides left to make room.
            if isHovered {
                Button {
                    model.reveal(item)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Pokaż w Finderze")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

private struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let banner = model.banner {
                BannerView(banner: banner)
            }
            if model.isApplying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.freeSpace ? "Ustawianie jako tylko online i zwalnianie miejsca…" : "Ustawianie jako tylko online…")
                        .font(.callout)
                }
            } else if !model.markedOnlineOnly.isEmpty {
                selectionBar
            } else {
                HStack {
                    Text("Odznacz element, aby przestał być dostępny offline.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let date = model.lastRefresh {
                        Text("Sprawdzono \(date.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.isOnline {
                Label("Brak internetu – po zmianie tych plików nie otworzysz do czasu połączenia.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tylko online: \(Plural.items(model.markedOnlineOnly.count))")
                        .font(.callout.weight(.medium))
                    if model.freeSpace, let size = model.selectedSize {
                        Text("Zwolni ok. \(Format.bytes(size))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Anuluj") { model.cancelSelection() }
                    .keyboardShortcut(.cancelAction)
                Button("Zastosuj") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isBoxRunning || !model.canChangeOfflineState)
            }
        }
    }
}

private struct BannerView: View {
    @EnvironmentObject private var model: AppModel
    let banner: Banner

    var body: some View {
        // Both icons sit on the first line of the message, also when it wraps onto several lines.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(tint)
            Text(banner.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                model.banner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Zamknij")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.1)))
    }

    private var symbol: String {
        switch banner.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
}
