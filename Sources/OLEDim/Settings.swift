import Foundation
import Combine

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

    @Published var autoEnabled: Bool { didSet { defaults.set(autoEnabled, forKey: "autoEnabled") } }
    @Published var autoMin: Double { didSet { defaults.set(autoMin, forKey: "autoMin") } }
    @Published var autoMax: Double { didSet { defaults.set(autoMax, forKey: "autoMax") } }
    /// Learned from manual slider moves while auto-adjust is on.
    @Published var autoOffset: Double { didSet { defaults.set(autoOffset, forKey: "autoOffset") } }

    @Published var idleDimEnabled: Bool { didSet { defaults.set(idleDimEnabled, forKey: "idleDimEnabled") } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: "idleMinutes") } }
    @Published var idleLevel: Double { didSet { defaults.set(idleLevel, forKey: "idleLevel") } }
    @Published var idleRespectsMedia: Bool { didSet { defaults.set(idleRespectsMedia, forKey: "idleRespectsMedia") } }

    @Published var fadeEnabled: Bool { didSet { defaults.set(fadeEnabled, forKey: "fadeEnabled") } }

    private init() {
        defaults.register(defaults: [
            "dayLevel": 70.0, "eveningLevel": 45.0, "nightLevel": 20.0,
            "autoEnabled": true, "autoMin": 5.0, "autoMax": 100.0, "autoOffset": 0.0,
            "idleDimEnabled": true, "idleMinutes": 5, "idleLevel": 5.0, "idleRespectsMedia": true,
            "fadeEnabled": true,
        ])
        dayLevel = defaults.double(forKey: "dayLevel")
        eveningLevel = defaults.double(forKey: "eveningLevel")
        nightLevel = defaults.double(forKey: "nightLevel")
        autoEnabled = defaults.bool(forKey: "autoEnabled")
        autoMin = defaults.double(forKey: "autoMin")
        autoMax = defaults.double(forKey: "autoMax")
        autoOffset = defaults.double(forKey: "autoOffset")
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


    /// Brightness for a light level: log-scaled between autoMin (darkness) and autoMax (~1000 lux), plus the learned offset.
    func autoLevel(lux: Double, includeOffset: Bool = true) -> Double {
        let t = min(1, log10(max(lux, 0) + 1) / 3)
        let base = autoMin + (autoMax - autoMin) * t
        return min(100, max(0, base + (includeOffset ? autoOffset : 0)))
    }
}
