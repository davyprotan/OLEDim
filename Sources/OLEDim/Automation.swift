import AppKit
import IOKit.pwr_mgt

/// Follows the ambient light sensor, and dims the monitor while the Mac sits idle (OLED burn-in protection).
final class Automation {
    private let controller: BrightnessController
    private let settings = Settings.shared
    private let sensor = AmbientLightSensor()

    private var timer: Timer?
    /// Exponentially smoothed lux so passing shadows don't cause flicker.
    private(set) var smoothedLux: Double?
    /// Brightness to return to when the user comes back; non-nil while idle-dimmed.
    private var levelBeforeIdle: Double?

    var hasSensor: Bool { sensor != nil }

    init(controller: BrightnessController) {
        self.controller = controller
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.smoothedLux = nil
        }
        schedule(interval: 2)
        tick()
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval / 4
    }

    /// Call when the user picks a brightness. With auto-adjust on, the difference from the curve is learned as an offset.
    func userChangedBrightness(to value: Double) {
        levelBeforeIdle = nil
        schedule(interval: 2)
        if settings.autoEnabled, let lux = smoothedLux {
            settings.autoOffset = value - settings.autoLevel(lux: lux, includeOffset: false)
        }
    }

    private func tick() {
        guard controller.isReady else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if let restore = levelBeforeIdle {
            guard idle < 2 || !settings.idleDimEnabled else { return }
            levelBeforeIdle = nil
            schedule(interval: 2)
            let target = settings.autoEnabled ? smoothedLux.map { settings.autoLevel(lux: $0) } ?? restore : restore
            controller.set(target, fade: settings.fadeEnabled)
            return
        }

        if settings.idleDimEnabled,
           idle >= Double(settings.idleMinutes * 60),
           !(settings.idleRespectsMedia && Self.somethingKeepsDisplayAwake()),
           controller.brightness > settings.idleLevel {
            levelBeforeIdle = controller.brightness
            controller.set(settings.idleLevel, fade: settings.fadeEnabled)
            schedule(interval: 0.3) // poll fast so waking the screen feels instant
            return
        }

        guard settings.autoEnabled, AmbientLightSensor.builtInDisplayIsActive(), let lux = sensor?.lux() else { return }
        let smoothed = smoothedLux.map { $0 * 0.7 + lux * 0.3 } ?? lux
        smoothedLux = smoothed
        // First run: treat the brightness the user already had as their preference for this light level.
        if !UserDefaults.standard.bool(forKey: "autoCalibrated") {
            UserDefaults.standard.set(true, forKey: "autoCalibrated")
            settings.autoOffset = controller.brightness - settings.autoLevel(lux: smoothed, includeOffset: false)
        }
        let target = settings.autoLevel(lux: smoothed).rounded()
        if abs(target - controller.brightness) >= 3 {
            controller.set(target, fade: settings.fadeEnabled)
        }
    }

    /// True when an app (video player, call, presentation) is holding a "keep display on" assertion.
    static func somethingKeepsDisplayAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
