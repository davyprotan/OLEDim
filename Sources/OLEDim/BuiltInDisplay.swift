import Foundation
import CoreGraphics

/// Reads the MacBook's built-in display brightness via the private DisplayServices framework.
enum BuiltInDisplay {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    static var id: CGDirectDisplayID? {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// True when the lid is open and the built-in display is in use.
    static var isActive: Bool { id != nil }

    static var isSupported: Bool { getBrightness != nil }

    /// Brightness from 0 to 1, or nil with the lid closed.
    static func brightness() -> Double? {
        guard let id, let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(id, &value) == 0 ? Double(value) : nil
    }
}
