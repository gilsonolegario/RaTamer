import Foundation
import IOKit
import IOKit.hid

public enum HIDLocatorError: Error {
    case noDeviceFound
    case openFailed(String)
}

public enum HIDLocator {
    public static let logitechVendorID: UInt32 = 0x046D
    public static let knownReceiverPIDs: Set<UInt16> = [
        0xC52B, 0xC52F, 0xC531, 0xC532, 0xC534,
        0xC539, 0xC53A, 0xC53F, 0xC548
    ]
    public static let hidppUsagePages: Set<Int> = [0xFF43, 0xFF00, 0xFF02]

    // IOHIDManager never enumerates the Unifying receiver on macOS 15/arm64
    // (even as root). The kernel registry path is the only reliable source.
    public static func openReceiver() throws -> HIDDevice {
        for service in allHIDDeviceServices() {
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            guard isLogitech(device) else { continue }
            let pairs = usagePairs(from: IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString))
            guard isHIDPPInterface(usagePairs: pairs) else { continue }
            if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                return IOHIDDeviceWrapper(device: device)
            }
        }
        throw HIDLocatorError.openFailed("No HID++ interface could be opened")
    }

    public static func listDevices() -> [String] {
        var lines: [String] = []
        for service in allHIDDeviceServices() {
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let vid = propertyInt(device, kIOHIDVendorIDKey as CFString)
            let pid = propertyInt(device, kIOHIDProductIDKey as CFString)
            let name = propertyString(device, kIOHIDProductKey as CFString)
            let pairs = usagePairs(from: IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString))
            let summary = pairs.map {
                String(format: "0x%04X/0x%02X", $0.page, $0.usage)
            }.joined(separator: ", ")
            lines.append(String(format: "vid=0x%04X pid=0x%04X product=%@ pairs=[%@]",
                                vid, pid, name, summary))
        }
        return lines
    }

    // MARK: - Pure helpers (unit-testable)

    public static func usagePairs(from property: Any?) -> [(page: Int, usage: Int)] {
        guard let array = property as? NSArray else { return [] }
        var result: [(page: Int, usage: Int)] = []
        for element in array {
            guard let dict = element as? NSDictionary,
                  let page = (dict["DeviceUsagePage"] as? NSNumber)?.intValue,
                  let usage = (dict["DeviceUsage"] as? NSNumber)?.intValue else { continue }
            result.append((page, usage))
        }
        return result
    }

    public static func isHIDPPInterface(usagePairs pairs: [(page: Int, usage: Int)]) -> Bool {
        return pairs.contains { hidppUsagePages.contains($0.page) }
    }

    // MARK: - IOKit internals

    private static func allHIDDeviceServices() -> [io_service_t] {
        let matching = IOServiceMatching("IOHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            services.append(service)
        }
        return services
    }

    private static func isLogitech(_ device: IOHIDDevice) -> Bool {
        return propertyInt(device, kIOHIDVendorIDKey as CFString) == Int(logitechVendorID)
    }

    private static func propertyInt(_ device: IOHIDDevice, _ key: CFString) -> Int {
        return (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
    }

    private static func propertyString(_ device: IOHIDDevice, _ key: CFString) -> String {
        return IOHIDDeviceGetProperty(device, key) as? String ?? "?"
    }
}
