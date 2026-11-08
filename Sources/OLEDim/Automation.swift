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
    /// Re-reads the monitor now and then: nothing else notices its own buttons, an input switch, or a write that never landed.
    private var lastResync = Date()
    private static let resyncInterval: TimeInterval = 30

    var hasSensor: Bool { sensor != nil }

    init(controller: BrightnessController) {
        self.controller = controller
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.smoothedLux = nil
            // Monitors often come back from sleep at their own stored level, and take a few seconds to answer DDC.
            for delay in [3.0, 10.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.controller.resync() }
            }
        }
        resetTimer()
    }

    /// Polls faster when the result has to feel immediate: waking from idle, or following the brightness keys.
    private func resetTimer() {
        let interval = levelBeforeIdle != nil ? 0.3 : settings.mode == .matchMac ? 0.4 : 2
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = interval / 4
        // .common, not the default mode: that one stops firing while the status menu is open or a slider is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
        // With the MacBook screen off the monitor goes black regardless of the curve, so there's nothing to learn.
        if let input = currentInput(), !Self.macScreenOff(mode: settings.mode, input: input) {
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
        if Date().timeIntervalSince(lastResync) >= Self.resyncInterval {
            lastResync = Date()
            controller.resync()
        }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if let restore = levelBeforeIdle {
            guard idle < 2 || !settings.idleDimEnabled else { return }
            levelBeforeIdle = nil
            resetTimer()
            let target = currentInput().map {
            Self.macScreenOff(mode: settings.mode, input: $0) ? settings.lowestLevel : settings.autoLevel(input: $0, mode: settings.mode)
        } ?? restore
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

        // MacBook screen off (lowest key step and below) means the monitor goes dark too.
        let target = Self.macScreenOff(mode: settings.mode, input: input)
            ? settings.lowestLevel
            : settings.autoLevel(input: input, mode: settings.mode).rounded()
        let threshold: Double = settings.mode == .matchMac ? 1 : 3
        if abs(target - controller.brightness) >= threshold {
            controller.set(target, fade: settings.fadeEnabled)
        }
    }

    static func macScreenOff(mode: BrightnessMode, input: Double) -> Bool {
        mode == .matchMac && input < 0.001
    }

    /// True when an app (video player, call, presentation) is holding a "keep display on" assertion.
    static func somethingKeepsDisplayAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
