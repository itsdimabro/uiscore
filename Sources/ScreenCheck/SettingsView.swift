import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import ScreenCheckCore

struct SettingsView: View {
    var openKeys: () -> Void
    @State private var launch = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .check)
            LabeledContent("Keys") {
                let c = KeyStore.claudeKeys()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Jev ···· \(KeyStore.get("jev").map { String($0.suffix(4)) } ?? "none")").font(.caption).foregroundStyle(.secondary)
                    Text(c.isEmpty ? "No Claude keys" : c.map { "Claude " + KeyRules.mask($0) }.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    Button("Edit keys…", action: openKeys)
                }
            }
            Toggle("Open at login", isOn: $launch).onChange(of: launch) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchError = nil }
                catch { launchError = "Could not change this. Move the app to Applications first."; launch = !on }
            }
            if let e = launchError { Text(e).font(.caption).foregroundStyle(.secondary) }
            Text("Keys are kept in your Mac's Keychain.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 380)
    }
}

extension KeyboardShortcuts.Name {
    static let check = Self("check", default: .init(.v, modifiers: [.command, .shift]))
}
