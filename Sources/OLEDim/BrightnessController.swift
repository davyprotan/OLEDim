import Foundation
import Combine

/// Owns the DDC displays and serialises writes so slider drags and fades never pile up on the I2C bus.
final class BrightnessController: ObservableObject {
    @Published private(set) var brightness: Double = 50
    @Published private(set) var displayNames: [String] = []
    /// False until the monitor's real brightness has been read, so nothing acts on the placeholder value.
    private(set) var isReady = false

    private var displays: [DDCDisplay] = []
    private let queue = DispatchQueue(label: "oledim.ddc")
    private let lock = NSLock()
    private var generation = 0

    init() { rescan() }

    func rescan() {
        queue.async {
            let found = DDCDisplay.all()
            let readGeneration = self.currentGeneration()
            let current = Self.readLuminance(from: found)
            DispatchQueue.main.async {
                self.displays = found
                self.displayNames = found.map(\.name)
                if let current { self.adopt(current, readAt: readGeneration) }
                self.isReady = !found.isEmpty
            }
        }
    }

    /// Re-reads what the monitor is really at, so changes made behind our back (wake, the monitor's own buttons,
    /// a write that never landed) don't leave `brightness` stale. Automation then corrects the monitor on its next tick.
    func resync() {
        let displays = self.displays
        guard !displays.isEmpty else { return }
        queue.async { self.readBack(displays) }
    }

    var hasDisplays: Bool { !displays.isEmpty }

    /// Runs on `queue`.
    private func readBack(_ displays: [DDCDisplay]) {
        let readGeneration = currentGeneration()
        guard let current = Self.readLuminance(from: displays) else { return }
        DispatchQueue.main.async { self.adopt(current, readAt: readGeneration) }
    }

    /// Ignores the reading if a newer set() started since, so it can't overwrite the value the user just picked.
    private func adopt(_ value: Double, readAt readGeneration: Int) {
        guard currentGeneration() == readGeneration, value != brightness else { return }
        brightness = value
    }

    private func currentGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    // A plain loop, not `lazy.compactMap(...).first`: that calls read() twice and force-unwraps the
    // second result, which crashed when the monitor stopped answering mid-rescan (e.g. on wake or replug).
    private static func readLuminance(from displays: [DDCDisplay]) -> Double? {
        for display in displays {
            if let value = display.read(.luminance) { return Double(value.current) }
        }
        return nil
    }

    /// Sets brightness on every external display. A newer call cancels any fade still in progress.
    func set(_ target: Double, fade: Bool) {
        let target = min(max(target.rounded(), 0), 100)
        let start = brightness
        brightness = target

        lock.lock(); generation += 1; let myGeneration = generation; lock.unlock()
        let displays = self.displays

        queue.async { [weak self] in
            guard let self else { return }
            let isCurrent = { self.lock.lock(); defer { self.lock.unlock() }; return self.generation == myGeneration }
            guard isCurrent() else { return } // superseded while queued (e.g. fast slider drag)

            let steps = fade ? max(1, min(20, Int(abs(target - start) / 2))) : 1
            var landed = true
            for step in 1...steps {
                guard isCurrent() else { return }
                let value = start + (target - start) * Double(step) / Double(steps)
                // map, not allSatisfy: every display must get the write even if an earlier one failed.
                landed = displays.map { $0.write(.luminance, value: UInt16(value.rounded())) }.allSatisfy { $0 }
                if steps > 1 { usleep(35_000) }
            }
            // `brightness` already claims the target; if the last write was lost, find out where the monitor really is.
            if !landed { self.readBack(displays) }
        }
    }
}
