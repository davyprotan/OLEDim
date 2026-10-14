import Foundation
import IOKit

// Private IOKit symbols used to talk I2C over Apple Silicon's display pipeline (same approach as m1ddc / MonitorControl).
typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

enum VCP: UInt8 {
    case luminance = 0x10
    case contrast = 0x12
}

/// One external display reachable over DDC/CI.
final class DDCDisplay {
    let service: IOAVService
    let name: String

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    init(service: IOAVService, name: String) {
        self.service = service
        self.name = name
    }

    /// Finds every external display exposed through DCPAVServiceProxy.
    static func all() -> [DDCDisplay] {
        var displays: [DDCDisplay] = []
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var lastProductName = "External Display"
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            let entryName = String(cString: nameBuf)

            // The display's product name appears on an AppleCLCD2 / IOMobileFramebufferShim node before its AV proxy.
            if let attrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let product = attrs["ProductAttributes"] as? [String: Any],
               let productName = product["ProductName"] as? String {
                lastProductName = productName
            }

            guard entryName == "DCPAVServiceProxy" else { continue }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard location == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            displays.append(DDCDisplay(service: service, name: lastProductName))
        }
        return displays
    }

    @discardableResult
    func write(_ vcp: VCP, value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, vcp.rawValue, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(0x6E ^ UInt8(Self.dataAddress), ^)
        for _ in 0..<3 {
            let result = packet.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            if result == kIOReturnSuccess { return true }
            usleep(20_000)
        }
        return false
    }

    /// Returns (current, max), or nil if the monitor didn't answer.
    func read(_ vcp: VCP) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
        request[3] = request[0..<3].reduce(0x6E ^ UInt8(Self.dataAddress), ^)
        for _ in 0..<4 {
            var reply = [UInt8](repeating: 0, count: 12)
            let wrote = request.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            usleep(40_000)
            let read = reply.withUnsafeMutableBytes {
                IOAVServiceReadI2C(service, Self.chipAddress, 0, $0.baseAddress!, UInt32($0.count))
            }
            // Reply: [src, len, 0x02, result, vcp, type, maxH, maxL, curH, curL, checksum]
            if wrote == kIOReturnSuccess, read == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp.rawValue {
                let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
                let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
                return (current, max)
            }
            usleep(30_000)
        }
        return nil
    }
}
