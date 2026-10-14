import AppKit
import IOKit.pwr_mgt

/// Drives the monitor from the room light or the MacBook's screen, and dims it while the Mac sits idle (OLED burn-in protection).
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
        resetTimer()
    }

    /// Polls faster when the result has to feel immediate: waking from idle, or following the brightness keys.
    private func resetTimer() {
        let interval = levelBeforeIdle != nil ? 0.3 : settings.mode == .matchMac ? 0.4 : 2
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval / 4
    }

    /// Call after the mode changes.
    func modeChanged() {
        smoothedLux = nil
        resetTimer()
        tick()
    }

    /// Call when the user picks a brightness. In an automatic mode, the difference from the curve is learned as an offset.
    func userChangedBrightness(to value: Double) {
        if levelBeforeIdle != nil {
            levelBeforeIdle = nil
            resetTimer()
        }
        if let input = currentInput() {
            settings.setOffset(value - settings.autoLevel(input: input, mode: settings.mode, includeOffset: false), for: settings.mode)
        }
    }

    /// The 0...1 signal the current mode follows, or nil in manual mode / with the lid closed.
    private func currentInput() -> Double? {
        switch settings.mode {
        case .manual: return nil
        case .roomLight: return smoothedLux.map(Settings.normalized(lux:))
        case .matchMac: return BuiltInDisplay.brightness()
        }
    }

    private func tick() {
        guard controller.isReady else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if let restore = levelBeforeIdle {
            guard idle < 2 || !settings.idleDimEnabled else { return }
            levelBeforeIdle = nil
            resetTimer()
            let target = currentInput().map { settings.autoLevel(input: $0, mode: settings.mode) } ?? restore
            controller.set(target, fade: settings.fadeEnabled)
            return
        }

        if settings.idleDimEnabled,
           idle >= Double(settings.idleMinutes * 60),
           !(settings.idleRespectsMedia && Self.somethingKeepsDisplayAwake()),
           controller.brightness > settings.idleLevel {
            levelBeforeIdle = controller.brightness
            controller.set(settings.idleLevel, fade: settings.fadeEnabled)
            resetTimer()
            return
        }

        // The light sensor sits beside the built-in screen, so both modes hold still with the lid closed.
        guard settings.mode != .manual, BuiltInDisplay.isActive else { return }

        if settings.mode == .roomLight {
            guard let lux = sensor?.lux() else { return }
            smoothedLux = smoothedLux.map { $0 * 0.7 + lux * 0.3 } ?? lux
        }
        guard let input = currentInput() else { return }

        // First use of a mode: treat the brightness the user already had as their preference.
        let calibratedKey = "calibrated.\(settings.mode.rawValue)"
        if !UserDefaults.standard.bool(forKey: calibratedKey) {
            UserDefaults.standard.set(true, forKey: calibratedKey)
            userChangedBrightness(to: controller.brightness)
        }

        let target = settings.autoLevel(input: input, mode: settings.mode).rounded()
        let threshold: Double = settings.mode == .matchMac ? 1 : 3
        if abs(target - controller.brightness) >= threshold {
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
