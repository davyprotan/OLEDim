import Foundation
import Combine

/// Where the monitor's brightness comes from.
enum BrightnessMode: String, CaseIterable {
    case manual = "Manual"
    case roomLight = "Match room light"
    case matchMac = "Match MacBook screen"
}

/// One-click brightness presets shown in the menu.
enum Period: String, CaseIterable {
    case day = "Day", evening = "Evening", night = "Night"
}

/// User preferences, persisted to UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var dayLevel: Double { didSet { defaults.set(dayLevel, forKey: "dayLevel") } }
    @Published var eveningLevel: Double { didSet { defaults.set(eveningLevel, forKey: "eveningLevel") } }
    @Published var nightLevel: Double { didSet { defaults.set(nightLevel, forKey: "nightLevel") } }

    @Published var mode: BrightnessMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var autoMin: Double { didSet { defaults.set(autoMin, forKey: "autoMin") } }
    @Published var autoMax: Double { didSet { defaults.set(autoMax, forKey: "autoMax") } }
    /// Learned from manual slider moves, kept separately for each automatic mode.
    @Published var roomOffset: Double { didSet { defaults.set(roomOffset, forKey: "roomOffset") } }
    @Published var macOffset: Double { didSet { defaults.set(macOffset, forKey: "macOffset") } }

    @Published var idleDimEnabled: Bool { didSet { defaults.set(idleDimEnabled, forKey: "idleDimEnabled") } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: "idleMinutes") } }
    @Published var idleLevel: Double { didSet { defaults.set(idleLevel, forKey: "idleLevel") } }
    @Published var idleRespectsMedia: Bool { didSet { defaults.set(idleRespectsMedia, forKey: "idleRespectsMedia") } }

    @Published var fadeEnabled: Bool { didSet { defaults.set(fadeEnabled, forKey: "fadeEnabled") } }

    private init() {
        defaults.register(defaults: [
            "dayLevel": 70.0, "eveningLevel": 45.0, "nightLevel": 20.0,
            "mode": BrightnessMode.roomLight.rawValue, "autoMin": 5.0, "autoMax": 100.0, "roomOffset": 0.0, "macOffset": 0.0,
            "idleDimEnabled": true, "idleMinutes": 5, "idleLevel": 5.0, "idleRespectsMedia": true,
            "fadeEnabled": true,
        ])
        dayLevel = defaults.double(forKey: "dayLevel")
        eveningLevel = defaults.double(forKey: "eveningLevel")
        nightLevel = defaults.double(forKey: "nightLevel")
        mode = BrightnessMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .roomLight
        autoMin = defaults.double(forKey: "autoMin")
        autoMax = defaults.double(forKey: "autoMax")
        roomOffset = defaults.double(forKey: "roomOffset")
        macOffset = defaults.double(forKey: "macOffset")
        idleDimEnabled = defaults.bool(forKey: "idleDimEnabled")
        idleMinutes = defaults.integer(forKey: "idleMinutes")
        idleLevel = defaults.double(forKey: "idleLevel")
        idleRespectsMedia = defaults.bool(forKey: "idleRespectsMedia")
        fadeEnabled = defaults.bool(forKey: "fadeEnabled")
    }

    func level(for period: Period) -> Double {
        switch period {
        case .day: return dayLevel
        case .evening: return eveningLevel
        case .night: return nightLevel
        }
    }


    func offset(for mode: BrightnessMode) -> Double {
        switch mode {
        case .manual: return 0
        case .roomLight: return roomOffset
        case .matchMac: return macOffset
        }
    }

    func setOffset(_ value: Double, for mode: BrightnessMode) {
        switch mode {
        case .manual: break
        case .roomLight: roomOffset = value
        case .matchMac: macOffset = value
        }
    }

    /// Maps a 0...1 input (log-scaled lux, or the MacBook's brightness) onto autoMin...autoMax.
    func autoLevel(input: Double, mode: BrightnessMode, includeOffset: Bool = true) -> Double {
        let base = autoMin + (autoMax - autoMin) * min(1, max(0, input))
        return min(100, max(0, base + (includeOffset ? offset(for: mode) : 0)))
    }

    /// Room light maps on a log scale so dim rooms get finer steps; ~1000 lux counts as fully bright.
    static func normalized(lux: Double) -> Double {
        min(1, log10(max(lux, 0) + 1) / 3)
    }
}
