import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(title: "Uruchamiaj przy logowaniu", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLoginNeedsApproval {
                    HStack {
                        Text("Wymaga zgody w Ustawieniach systemowych → Ogólne → Rzeczy otwierane podczas logowania.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Otwórz") { model.openLoginItemsSettings() }.controlSize(.small)
                    }
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SwitchRow(title: "Po odznaczeniu usuwaj pobrane pliki z dysku", isOn: $model.freeSpace)
                Text(model.freeSpace
                     ? "Miejsce zwalnia się od razu. Pliki zostają widoczne w Finderze i pobiorą się przy otwarciu. Pliki z niewysłanymi zmianami nie są usuwane."
                     : "Box przestanie trzymać pliki offline, ale pobrane kopie zostaną na dysku, dopóki Box lub macOS ich nie usunie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Odświeżaj listę co")
                Spacer()
                Picker("", selection: $model.refreshMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Divider()

            HStack {
                Text("Debox \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Zakończ Debox") { NSApp.terminate(nil) }
                Button("Gotowe") { model.showingSettings = false }
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
