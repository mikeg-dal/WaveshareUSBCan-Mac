import Foundation

/// CAN controller mode. Values are the byte the adapter's settings command expects.
enum CANMode: UInt8, CaseIterable, Identifiable, Sendable {
    case normal = 0x00
    case loopback = 0x01
    case silent = 0x02
    case loopbackSilent = 0x03

    var id: UInt8 { rawValue }

    /// Labels kept identical to the reference application, including its spelling of
    /// "Slient", so screenshots and documentation line up.
    var label: String {
        switch self {
        case .normal: "Normal"
        case .loopback: "Loop back mode"
        case .silent: "Slient mode"
        case .loopbackSilent: "Loop back & Slient mode"
        }
    }

    /// Loopback modes never reach the wire, so they are safe with nothing attached.
    var touchesBus: Bool { self == .normal || self == .silent }
}

enum CANFrameType: UInt8, CaseIterable, Identifiable, Sendable {
    case standard = 0x01
    case extended = 0x02

    var id: UInt8 { rawValue }
    var label: String { self == .standard ? "Standard Frame" : "Extended Frame" }
    var isExtended: Bool { self == .extended }
}

enum CANFrameFormat: UInt8, CaseIterable, Identifiable, Sendable {
    case data = 0x01
    case remote = 0x02

    var id: UInt8 { rawValue }
    var label: String { self == .data ? "Data frame" : "Remote frame" }
}

/// Serial framing. The adapter speaks both; the host must match whichever is selected.
enum WireProtocol: String, CaseIterable, Identifiable, Sendable {
    case fixed20 = "Fixed"
    case variable = "Variable"

    var id: String { rawValue }
    var label: String { self == .fixed20 ? "Fixed 20 bytes" : "Variable length" }
}

/// Bit rate codes understood by the adapter's settings command.
enum CANSpeed: UInt8, CaseIterable, Identifiable, Sendable {
    case bps1M = 0x01
    case bps800k = 0x02
    case bps500k = 0x03
    case bps400k = 0x04
    case bps250k = 0x05
    case bps200k = 0x06
    case bps125k = 0x07
    case bps100k = 0x08
    case bps50k = 0x09
    case bps20k = 0x0A
    case bps10k = 0x0B
    case bps5k = 0x0C

    var id: UInt8 { rawValue }

    var bitsPerSecond: Int {
        switch self {
        case .bps1M: 1_000_000
        case .bps800k: 800_000
        case .bps500k: 500_000
        case .bps400k: 400_000
        case .bps250k: 250_000
        case .bps200k: 200_000
        case .bps125k: 125_000
        case .bps100k: 100_000
        case .bps50k: 50_000
        case .bps20k: 20_000
        case .bps10k: 10_000
        case .bps5k: 5_000
        }
    }

    var label: String {
        bitsPerSecond >= 1_000_000
            ? "\(bitsPerSecond / 1_000_000)M"
            : "\(bitsPerSecond / 1_000)K"
    }
}

/// Manual bit-timing segments, used when "Manual Set Baud Rate" is on.
enum SyncJumpWidth: UInt8, CaseIterable, Identifiable, Sendable {
    case tq1 = 1, tq2, tq3, tq4
    var id: UInt8 { rawValue }
    var label: String { "CAN_SJW_\(rawValue)tq" }
}

enum BitSegment1: UInt8, CaseIterable, Identifiable, Sendable {
    case tq1 = 1, tq2, tq3, tq4, tq5, tq6, tq7, tq8
    case tq9, tq10, tq11, tq12, tq13, tq14, tq15, tq16
    var id: UInt8 { rawValue }
    var label: String { "CAN_BS1_\(rawValue)tq" }
}

enum BitSegment2: UInt8, CaseIterable, Identifiable, Sendable {
    case tq1 = 1, tq2, tq3, tq4, tq5, tq6, tq7, tq8
    var id: UInt8 { rawValue }
    var label: String { "CAN_BS2_\(rawValue)tq" }
}

/// How received IDs are forwarded to the host, mirroring the reference app's
/// "Configure the receive ID" radio group.
enum ReceiveUploadMode: String, CaseIterable, Identifiable, Sendable {
    case dontUpload = "Don't upload"
    case uploadOnly = "Upload only"
    case allUploaded = "All Uploaded"

    var id: String { rawValue }
}

/// Everything the adapter needs in one settings command.
struct AdapterSettings: Equatable, Sendable {
    var mode: CANMode = .normal
    var frameType: CANFrameType = .standard
    var speed: CANSpeed = .bps250k
    var wireProtocol: WireProtocol = .fixed20

    var manualBitTiming: Bool = false
    var syncJumpWidth: SyncJumpWidth = .tq1
    var bitSegment1: BitSegment1 = .tq6
    var bitSegment2: BitSegment2 = .tq5
    var prescaler: Int = 12

    var filterID: UInt32 = 0
    var maskID: UInt32 = 0

    /// Automatic retransmission. The reference app's "Only Send once" inverts this.
    var sendOnce: Bool = false

    /// The CH340 bridge runs at a fixed 2 Mbaud; exposed because the adapter's own
    /// rate can be changed from the Special Features panel.
    var serialBaud: Int = 2_000_000

    /// Effective bit rate from the manual timing fields. The adapter's CAN peripheral
    /// is clocked at 36 MHz, divided by the prescaler and the total quanta per bit.
    var computedBitRate: Double {
        let quanta = Double(1 + bitSegment1.rawValue + bitSegment2.rawValue)
        guard prescaler > 0, quanta > 0 else { return 0 }
        return 36_000_000.0 / Double(prescaler) / quanta
    }

    var computedBitRateText: String {
        String(format: "%.3fkbps", computedBitRate / 1000.0)
    }
}
