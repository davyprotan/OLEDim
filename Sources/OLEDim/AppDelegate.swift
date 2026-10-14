import AppKit
import Combine
import SwiftUI

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

        let auto = NSMenuItem(title: "Auto-adjust to room light", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = settings.autoEnabled ? .on : .off
        if !automation.hasSensor {
            auto.title = "Auto-adjust (no light sensor found)"
            auto.isEnabled = false
        } else if settings.autoEnabled, let lux = automation.smoothedLux {
            auto.title += " (\(Int(lux)) lux)"
        }
        menu.addItem(auto)

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
        slider = NSSlider(value: controller.brightness, minValue: 0, maxValue: 100, target: self, action: #selector(sliderMoved(_:)))
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
        // A preset is an explicit choice, so it takes over from auto-adjust.
        settings.autoEnabled = false
        automation.userChangedBrightness(to: settings.level(for: period))
        controller.set(settings.level(for: period), fade: settings.fadeEnabled)
    }

    @objc private func toggleAuto() {
        settings.autoEnabled.toggle()
    }

    @objc private func toggleIdle() {
        settings.idleDimEnabled.toggle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
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
