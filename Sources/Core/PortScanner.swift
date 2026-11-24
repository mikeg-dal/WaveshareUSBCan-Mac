import Foundation
import IOKit
import IOKit.serial
import IOKit.usb

struct SerialPortInfo: Identifiable, Hashable, Sendable {
    var path: String
    var displayName: String
    var vendorID: Int?
    var productID: Int?

    var id: String { path }

    /// The adapter's CH340 bridge.
    var isUSBCANAdapter: Bool {
        vendorID == PortScanner.ch340VendorID && productID == PortScanner.ch340ProductID
    }

    /// WCH's driver names the node wchusbserial; Apple's names it usbserial. Useful
    /// because only one of those two drivers can actually reach 2,000,000 baud.
    var looksLikeWCHDriver: Bool { path.contains("wchusbserial") }
}

/// Finds serial ports and identifies which one is the adapter.
///
/// Matching on the USB id rather than the device path matters: macOS renames
/// /dev/cu.* according to the USB port, so a hardcoded path breaks as soon as the
/// adapter is moved to a different socket.
enum PortScanner {
    static let ch340VendorID = 0x1A86
    static let ch340ProductID = 0x7523

    static func scan() -> [SerialPortInfo] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        let dict = matching as NSMutableDictionary
        dict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var results: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = stringProperty(service, kIOCalloutDeviceKey) else { continue }

            let name = stringProperty(service, kIOTTYDeviceKey) ?? (path as NSString).lastPathComponent
            let (vid, pid) = usbIdentifiers(for: service)
            results.append(
                SerialPortInfo(path: path, displayName: name, vendorID: vid, productID: pid)
            )
        }

        // Adapters first, then alphabetical, so the right port is preselected.
        return results.sorted {
            if $0.isUSBCANAdapter != $1.isUSBCANAdapter { return $0.isUSBCANAdapter }
            return $0.path < $1.path
        }
    }

    /// The single attached adapter, if there is exactly one.
    static func findAdapter() -> SerialPortInfo? {
        let adapters = scan().filter(\.isUSBCANAdapter)
        return adapters.count == 1 ? adapters.first : adapters.first
    }

    // MARK: - IORegistry helpers

    private static func stringProperty(_ service: io_object_t, _ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return cf as? String
    }

    /// Walks up the USB device tree looking for idVendor / idProduct, which live on an
    /// ancestor of the serial node rather than on the node itself.
    private static func usbIdentifiers(for service: io_object_t) -> (Int?, Int?) {
        var current = service
        var retained = false
        defer { if retained { IOObjectRelease(current) } }

        for _ in 0..<8 {
            if let vid = intProperty(current, "idVendor"),
               let pid = intProperty(current, "idProduct") {
                return (vid, pid)
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS
            else { break }
            if retained { IOObjectRelease(current) }
            current = parent
            retained = true
        }
        return (nil, nil)
    }

    private static func intProperty(_ service: io_object_t, _ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return (cf as? NSNumber)?.intValue
    }
}
