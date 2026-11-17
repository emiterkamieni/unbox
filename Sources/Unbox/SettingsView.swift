import AppKit
import SwiftUI
import UnboxKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(title: L10n.text("Launch at login", "Uruchamiaj przy logowaniu"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLoginNeedsApproval {
                    HStack {
                        Text(L10n.text("Needs approval in System Settings.", "Wymaga zgody w Ustawieniach systemowych."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L10n.text("Open", "Otwórz")) { model.openLoginItemsSettings() }.controlSize(.small)
                    }
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(title: L10n.text("Remove downloaded files after unchecking", "Po odznaczeniu usuwaj pobrane pliki z dysku"),
                          isOn: $model.freeSpace)
                Caption(model.freeSpace
                        ? L10n.text("Space is freed right away. Files stay visible in Finder and download again when opened. Files with unsent changes are kept.",
                                    "Miejsce zwalnia się od razu. Pliki zostają widoczne w Finderze i pobiorą się przy otwarciu. Pliki z niewysłanymi zmianami nie są usuwane.")
                        : L10n.text("Box stops keeping the files offline, but the downloaded copies stay on disk until Box or macOS removes them.",
                                    "Box przestanie trzymać pliki offline, ale pobrane kopie zostaną na dysku, dopóki Box lub macOS ich nie usunie."))
            }

            MenuRow(title: L10n.text("Refresh the list every", "Odświeżaj listę co"), selection: $model.refreshMinutes) {
                ForEach([1, 5, 15, 30], id: \.self) { minutes in
                    Text(L10n.format("%ld min", "%ld min", minutes)).tag(minutes)
                }
            }

            MenuRow(title: L10n.text("Language", "Język"), selection: $model.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(title: L10n.text("Notify about new versions", "Powiadamiaj o nowych wersjach"),
                          isOn: $updates.notifyAboutUpdates)
                Caption(L10n.text("Checks for updates every 24 hours.", "Sprawdza aktualizacje co 24 godziny."))
            }

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.format("Version %@", "Wersja %@", updates.currentVersion))
                    if let version = updates.availableVersion {
                        Text(L10n.format("unbox %@ is available.", "Dostępna jest wersja unbox %@.", version))
                            .font(.caption)
                            .foregroundStyle(Brand.blue)
                    }
                }
                Spacer()
                Button(L10n.text("Check for Updates…", "Sprawdź aktualizacje…")) { updates.checkForUpdates() }
            }

            Divider()

            HStack {
                Button(L10n.text("Quit unbox", "Zakończ unbox")) { NSApp.terminate(nil) }
                Spacer()
                Button(L10n.text("Done", "Gotowe")) { model.showingSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(14)
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct MenuRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: $selection, content: options)
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
