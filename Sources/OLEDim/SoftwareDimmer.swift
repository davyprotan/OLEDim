import CoreGraphics
import Foundation

/// Dims external displays below their own minimum by scaling the gamma table.
/// macOS throws the table away when the app quits (or crashes), on display reconfiguration and sometimes on wake,
/// so `reapply()` is called from the periodic resync and after rescans.
final class SoftwareDimmer {
    /// 1 = untouched; lower values scale the light output (linear light, not signal).
    private(set) var factor: Double = 1

    /// Sets the share of light (0...1) the external displays keep. Main thread only.
    func set(light: Double) {
        let light = min(1, max(0, light))
        guard light != factor else { return }
        factor = light
        apply()
    }

    func reapply() {
        if factor < 1 { apply() }
    }

    private func apply() {
        guard factor < 1 else {
            CGDisplayRestoreColorSyncSettings()
            return
        }
        // The table is gamma-encoded; scaling it by light^(1/2.2) scales the emitted light by `light`.
        let scale = Float(pow(factor, 1 / 2.2))
        for id in Self.externalDisplays() {
            CGSetDisplayTransferByFormula(id, 0, scale, 1, 0, scale, 1, 0, scale, 1)
        }
    }

    private static func externalDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }
}
