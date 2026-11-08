import AppKit
import Combine
import SwiftUI
import os

let log = Logger(subsystem: "io.github.oledim", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = BrightnessController()
    private lazy var automation = Automation(controller: controller)
    private let settings = Settings.shared

    private var statusItem: NSStatusItem!
    private var slider: NSSlider!
    private var valueLabel: NSTextField!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "OLEDim")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.$brightness.receive(on: RunLoop.main).sink { [weak self] value in
            self?.slider?.doubleValue = value
            self?.valueLabel?.stringValue = "\(Int(value))%"
        }.store(in: &cancellables)

        // Turning software dimming off has to lift a level that's below 0 now, even in manual mode.
        settings.$softwareDimEnabled.dropFirst().receive(on: RunLoop.main).sink { [weak self] enabled in
            guard let self, !enabled, self.controller.brightness < 0 else { return }
            self.controller.set(0, fade: self.settings.fadeEnabled)
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.rescan()
        }

        _ = automation
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = controller.displayNames.first ?? "No external display found"
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(sliderItem())
        menu.addItem(.separator())

        for period in Period.allCases {
            let level = settings.level(for: period)
            let item = NSMenuItem(title: "\(period.rawValue) — \(Int(level))%", action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = period.rawValue
            item.state = Int(controller.brightness) == Int(level) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        for mode in BrightnessMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            if mode == .roomLight && !automation.hasSensor {
                item.title += " (no light sensor)"
                item.isEnabled = false
            } else if mode == .matchMac && !BuiltInDisplay.isSupported {
                item.isEnabled = false
            } else if mode == settings.mode && mode != .manual && !BuiltInDisplay.isActive {
                item.title += " (paused, lid closed)"
            } else if mode == .roomLight && settings.mode == .roomLight, let lux = automation.smoothedLux {
                item.title += " (\(Int(lux)) lux)"
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let idle = NSMenuItem(title: "Dim when idle (\(settings.idleMinutes) min)", action: #selector(toggleIdle), keyEquivalent: "")
        idle.target = self
        idle.state = settings.idleDimEnabled ? .on : .off
        menu.addItem(idle)

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(withTitle: "Quit OLEDim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func sliderItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        slider = MenuSlider(value: controller.brightness, minValue: settings.minLevel, maxValue: 100, target: self, action: #selector(sliderMoved(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 16, y: 6, width: 170, height: 20)
        valueLabel = NSTextField(labelWithString: "\(Int(controller.brightness))%")
        valueLabel.frame = NSRect(x: 192, y: 8, width: 40, height: 16)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        view.addSubview(slider)
        view.addSubview(valueLabel)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        automation.userChangedBrightness(to: sender.doubleValue)
        controller.set(sender.doubleValue, fade: false)
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let period = Period(rawValue: raw) else { return }
        // A preset is an explicit choice, so it switches to manual control.
        settings.mode = .manual
        automation.modeChanged()
        automation.userChangedBrightness(to: settings.level(for: period))
        controller.set(settings.level(for: period), fade: settings.fadeEnabled)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = BrightnessMode(rawValue: raw) else { return }
        settings.mode = mode
        automation.modeChanged()
    }

    @objc private func toggleIdle() {
        settings.idleDimEnabled.toggle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(onModeChange: { [weak self] in
                self?.automation.modeChanged()
            })))
            window.title = "OLEDim Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// A slider that, once clicked, takes the left/right arrow keys (1% a press, 10% with Shift).
/// NSSlider only becomes first responder with Full Keyboard Access on, and inside a menu the arrows would otherwise move
/// the menu highlight, so it claims first responder on click and handles the arrows itself.
private final class MenuSlider: NSSlider {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.specialKey {
        case .leftArrow?: nudge(by: -step)
        case .rightArrow?: nudge(by: step)
        default: super.keyDown(with: event)
        }
    }

    private func nudge(by delta: Double) {
        doubleValue = min(maxValue, max(minValue, doubleValue.rounded() + delta))
        sendAction(action, to: target)
    }
}
