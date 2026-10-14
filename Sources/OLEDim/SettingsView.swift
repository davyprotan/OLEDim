import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Presets") {
                levelSlider("Day", value: $settings.dayLevel)
                levelSlider("Evening", value: $settings.eveningLevel)
                levelSlider("Night", value: $settings.nightLevel)
            }

            Section {
                Toggle("Auto-adjust to room light", isOn: $settings.autoEnabled)
                levelSlider("Darkest", value: $settings.autoMin)
                levelSlider("Brightest", value: $settings.autoMax)
                HStack {
                    Text("Your adjustment: \(settings.autoOffset >= 0 ? "+" : "")\(Int(settings.autoOffset.rounded()))%")
                    Spacer()
                    Button("Reset") { settings.autoOffset = 0 }.disabled(settings.autoOffset == 0)
                }
            } header: {
                Text("Auto-adjust")
            } footer: {
                Text("Uses your MacBook's light sensor. Move the menu slider while auto-adjust is on and it learns your preference.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 400)
        .fixedSize()
    }

    private func levelSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0...100, step: 1)
            Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }

}
