import AppKit
import ServiceManagement

// CLI mode: `OLEDim get` / `OLEDim set <0-100>` / `OLEDim login on|off` for scripting and testing.
let args = CommandLine.arguments.dropFirst()
if args.first == "login" {
    do {
        if args.dropFirst().first == "off" { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        print("Launch at login: \(SMAppService.mainApp.status == .enabled ? "on" : "off")")
        exit(0)
    } catch {
        print("Couldn't change launch at login: \(error.localizedDescription)")
        exit(1)
    }
}
if let command = args.first, ["get", "set", "list"].contains(command) {
    let displays = DDCDisplay.all()
    guard !displays.isEmpty else { print("No external DDC displays found"); exit(1) }
    switch command {
    case "list":
        displays.enumerated().forEach { print("[\($0.offset)] \($0.element.name)") }
    case "get":
        for d in displays {
            if let v = d.read(.luminance) { print("\(d.name): \(v.current)/\(v.max)") } else { print("\(d.name): no reply") }
        }
    default:
        guard let value = args.dropFirst().first.flatMap(UInt16.init), value <= 100 else { print("usage: OLEDim set <0-100>"); exit(1) }
        for d in displays { print("\(d.name): \(d.write(.luminance, value: value) ? "ok" : "failed")") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
