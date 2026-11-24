import Foundation

/// One CAN frame as it appears in the trace view.
struct CANFrame: Identifiable, Hashable, Sendable {
    enum Direction: String, Sendable {
        case send = "Send"
        case received = "Received"
    }

    let id = UUID()
    var sequence: Int
    var direction: Direction
    var timestamp: Date
    var isExtended: Bool
    var isRemote: Bool
    var canID: UInt32
    var data: [UInt8]

    var dlc: Int { isRemote ? remoteLength : data.count }
    private var remoteLength: Int { data.count }

    /// "Data frame" / "Remote frame", matching the reference application's wording.
    var frameFormatText: String { isRemote ? "Remote frame" : "Data frame" }
    /// "Standard frame" / "Extended frame".
    var frameTypeText: String { isExtended ? "Extended frame" : "Standard frame" }

    var idText: String { "0x" + String(format: "%08X", canID) }
    var dataText: String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }

    var timeText: String {
        Self.timeFormatter.string(from: timestamp)
    }

    /// Matches the reference application's "hh:mm:ss zzz" column.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// A key that identifies "the same" frame for overlay display, which collapses
    /// repeats of one ID onto a single row instead of scrolling.
    var overlayKey: String { "\(direction.rawValue)-\(canID)-\(isExtended)-\(isRemote)" }
}

extension Array where Element == UInt8 {
    /// Parses "00 11 22" or "001122" into bytes, ignoring stray whitespace.
    static func fromHexString(_ s: String) -> [UInt8]? {
        let cleaned = s.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        return out
    }

    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
