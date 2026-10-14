import Foundation
import CoreGraphics

// Private IOHIDEventSystem calls for reading the MacBook's ambient light sensor on Apple Silicon.
private typealias HIDClient = CFTypeRef
@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<HIDClient>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ client: HIDClient, _ matching: CFDictionary)
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ client: HIDClient) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

final class AmbientLightSensor {
    private static let eventType: Int64 = 12 // kIOHIDEventTypeAmbientLightSensor
    private let client: HIDClient
    private let service: CFTypeRef

    init?() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
        guard let service = (IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef])?.first else { return nil }
        self.client = client
        self.service = service
    }

    /// Current illuminance in lux, or nil if the sensor has nothing to report.
    func lux() -> Double? {
        guard let event = IOHIDServiceClientCopyEvent(service, Self.eventType, 0, 0)?.takeRetainedValue() else { return nil }
        return IOHIDEventGetFloatValue(event, Int32(Self.eventType << 16))
    }

    /// The sensor sits beside the built-in display, so readings are meaningless with the lid closed.
    static func builtInDisplayIsActive() -> Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }
}
