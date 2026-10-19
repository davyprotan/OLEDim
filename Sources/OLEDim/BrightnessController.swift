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
            // A plain loop, not `lazy.compactMap(...).first`: that calls read() twice and force-unwraps the
            // second result, which crashed when the monitor stopped answering mid-rescan (e.g. on wake or replug).
            var current: (current: UInt16, max: UInt16)?
            for display in found {
                if let value = display.read(.luminance) { current = value; break }
            }
            DispatchQueue.main.async {
                self.displays = found
                self.displayNames = found.map(\.name)
                if let current { self.brightness = Double(current.current) }
                self.isReady = !found.isEmpty
            }
        }
    }

    var hasDisplays: Bool { !displays.isEmpty }

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
            for step in 1...steps {
                guard isCurrent() else { return }
                let value = start + (target - start) * Double(step) / Double(steps)
                displays.forEach { $0.write(.luminance, value: UInt16(value.rounded())) }
                if steps > 1 { usleep(35_000) }
            }
        }
    }
}
