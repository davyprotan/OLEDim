import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    var onModeChange: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Presets") {
                levelSlider("Day", value: $settings.dayLevel)
                levelSlider("Evening", value: $settings.eveningLevel)
                levelSlider("Night", value: $settings.nightLevel)
            }

            Section {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(BrightnessMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if settings.mode != .manual {
                    levelSlider("Darkest", value: $settings.autoMin)
                    levelSlider("Brightest", value: $settings.autoMax)
                    HStack {
                        let offset = Int(settings.offset(for: settings.mode).rounded())
                        Text("Your adjustment: \(offset >= 0 ? "+" : "")\(offset)%")
                        Spacer()
                        Button("Reset") { settings.setOffset(0, for: settings.mode) }.disabled(offset == 0)
                    }
                }
            } header: {
                Text("Brightness")
            } footer: {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Dim when idle", isOn: $settings.idleDimEnabled)
                Stepper("After \(settings.idleMinutes) min", value: $settings.idleMinutes, in: 1...60)
                levelSlider("Dim to", value: $settings.idleLevel)
                Toggle("Not while video or calls keep the screen awake", isOn: $settings.idleRespectsMedia)
            } header: {
                Text("Burn-in protection")
            } footer: {
                Text("Brightness comes back as soon as you move the mouse or type.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Fade between levels", isOn: $settings.fadeEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.mode) { _ in onModeChange() }
        .frame(width: 400)
        .fixedSize()
    }

    private var footer: String {
        switch settings.mode {
        case .manual: return "Set brightness with the menu bar slider or presets."
        case .roomLight: return "Follows your MacBook's light sensor. Move the menu slider and it learns your preference."
        case .matchMac: return "Follows your MacBook screen, including the brightness keys and macOS auto-brightness. Move the menu slider and it learns your preference."
        }
    }

    private func levelSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0...100, step: 1)
            Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }

}
