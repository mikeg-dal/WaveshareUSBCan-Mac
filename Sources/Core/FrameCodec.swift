import Foundation

/// Wire format for the Waveshare USB-CAN-A.
///
/// Every layout here was recovered from the vendor's own Windows application
/// (USBCANV2.12.exe) and cross-checked against a working Python implementation,
/// so the byte order and checksum rule are the adapter's, not a guess.
///
/// Command frames all look like:
///
///     0xAA 0x55 <cmd> <payload...> <checksum>
///     checksum = sum of every byte from index 2 up to, but not including, the checksum
///
enum FrameCodec {
    static let start: UInt8 = 0xAA
    static let end: UInt8 = 0x55

    static let cmdSettings: UInt8 = 0x12
    static let cmdReceiveFilterAll: UInt8 = 0x10
    static let cmdReceiveFilterOnly: UInt8 = 0x11

    /// Sum of `bytes[2...]`, truncated to a byte.
    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    // MARK: - Settings

    /// The 20-byte settings command. Sent by "Set and Start".
    static func settingsCommand(_ s: AdapterSettings) -> [UInt8] {
        var body: [UInt8] = []
        body.append(cmdSettings)
        body.append(s.speed.rawValue)
        body.append(s.frameType.rawValue)
        body.append(contentsOf: withUnsafeBytes(of: s.filterID.littleEndian) { Array($0) })
        body.append(contentsOf: withUnsafeBytes(of: s.maskID.littleEndian) { Array($0) })
        body.append(s.mode.rawValue)
        body.append(s.sendOnce ? 0x00 : 0x01)   // automatic retransmission
        body.append(contentsOf: [0, 0, 0, 0])   // reserved

        var frame: [UInt8] = [start, end]
        frame.append(contentsOf: body)
        frame.append(checksum(body[body.startIndex...]))
        precondition(frame.count == 20, "settings command must be 20 bytes")
        return frame
    }

    // MARK: - Data frames

    /// Fixed 20-byte data frame.
    ///
    ///     AA 55 01 <1=std|2=ext> <1=data|2=remote> <ID x4 LE> <DLC>
    ///     <data x8, zero padded> <reserved> <checksum>
    static func fixedDataFrame(
        canID: UInt32,
        data: [UInt8],
        type: CANFrameType,
        format: CANFrameFormat
    ) -> [UInt8] {
        let payload = Array(data.prefix(8))
        var body: [UInt8] = [0x01, type.rawValue, format.rawValue]
        body.append(contentsOf: withUnsafeBytes(of: canID.littleEndian) { Array($0) })
        body.append(UInt8(payload.count))
        body.append(contentsOf: payload)
        body.append(contentsOf: [UInt8](repeating: 0, count: 8 - payload.count))
        body.append(0)                           // reserved

        var frame: [UInt8] = [start, end]
        frame.append(contentsOf: body)
        frame.append(checksum(body[body.startIndex...]))
        precondition(frame.count == 20, "fixed data frame must be 20 bytes")
        return frame
    }

    /// Variable-length data frame.
    ///
    ///     AA <0xC0 | ext<<5 | rtr<<4 | dlc> <ID, LSB first, 2 or 4 bytes> <data> 55
    static func variableDataFrame(
        canID: UInt32,
        data: [UInt8],
        type: CANFrameType,
        format: CANFrameFormat
    ) -> [UInt8] {
        let isExtended = type.isExtended
        let isRemote = format == .remote
        let payload = isRemote ? [] : Array(data.prefix(8))

        var typeByte: UInt8 = 0xC0 | UInt8(payload.count & 0x0F)
        if isExtended { typeByte |= 0x20 }
        if isRemote { typeByte |= 0x10 }

        var frame: [UInt8] = [start, typeByte]
        let idBytes = withUnsafeBytes(of: canID.littleEndian) { Array($0) }
        frame.append(contentsOf: isExtended ? idBytes : Array(idBytes.prefix(2)))
        frame.append(contentsOf: payload)
        frame.append(end)
        return frame
    }

    static func dataFrame(
        canID: UInt32,
        data: [UInt8],
        type: CANFrameType,
        format: CANFrameFormat,
        wire: WireProtocol
    ) -> [UInt8] {
        switch wire {
        case .fixed20: fixedDataFrame(canID: canID, data: data, type: type, format: format)
        case .variable: variableDataFrame(canID: canID, data: data, type: type, format: format)
        }
    }

    // MARK: - Receive ID filter

    /// "Configure the receive ID". At most 50 IDs, which the adapter enforces.
    ///
    ///     AA 55 <0x10|0x11> <count> <ID x4 LE each> <checksum>
    static func receiveFilterCommand(ids: [UInt32], mode: ReceiveUploadMode) -> [UInt8] {
        let capped = Array(ids.prefix(50))
        let cmd: UInt8 = (mode == .allUploaded) ? cmdReceiveFilterAll : cmdReceiveFilterOnly
        let list: [UInt32] = (mode == .dontUpload) ? [] : capped

        var body: [UInt8] = [cmd, UInt8(list.count)]
        for id in list {
            body.append(contentsOf: withUnsafeBytes(of: id.littleEndian) { Array($0) })
        }
        var frame: [UInt8] = [start, end]
        frame.append(contentsOf: body)
        frame.append(checksum(body[body.startIndex...]))
        return frame
    }

    static let maxReceiveFilterIDs = 50
}

/// Incremental parser. Serial delivers arbitrary chunks, so bytes are accumulated
/// and whole frames are pulled off the front as they complete.
///
/// A payload byte may itself be 0x55, so frames are measured by the length implied
/// by the type byte and never found by scanning for the terminator.
struct FrameDecoder {
    private var buffer: [UInt8] = []
    var wire: WireProtocol

    init(wire: WireProtocol) { self.wire = wire }

    mutating func reset() { buffer.removeAll(keepingCapacity: true) }

    mutating func append(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
        if buffer.count > 1 << 16 {
            buffer.removeFirst(buffer.count - (1 << 16))
        }
    }

    /// Pulls every complete frame currently buffered.
    mutating func drain() -> [(canID: UInt32, data: [UInt8], isExtended: Bool, isRemote: Bool)] {
        var out: [(UInt32, [UInt8], Bool, Bool)] = []
        while let frame = next() { out.append(frame) }
        return out.map { (canID: $0.0, data: $0.1, isExtended: $0.2, isRemote: $0.3) }
    }

    /// Dispatches on what is actually in the buffer rather than on the configured
    /// protocol.
    ///
    /// This matters: the adapter answers in variable-length framing after the 0x12
    /// settings command even when the host is sending fixed 20-byte frames. A decoder
    /// pinned to the configured mode silently discards every reply, which looks
    /// exactly like an adapter that is not responding.
    private mutating func next() -> (UInt32, [UInt8], Bool, Bool)? {
        while true {
            guard let startIdx = buffer.firstIndex(of: FrameCodec.start) else {
                buffer.removeAll(keepingCapacity: true)
                return nil
            }
            if startIdx > 0 { buffer.removeFirst(startIdx) }
            guard buffer.count >= 2 else { return nil }

            if buffer[1] == FrameCodec.end {
                // 0xAA 0x55 — either a fixed 20-byte data frame or a command echo.
                guard buffer.count >= 3 else { return nil }
                guard buffer[2] == 0x01 else {
                    buffer.removeFirst()        // command echo, not a data frame
                    continue
                }
                if let f = takeFixed() { return f }
                return nil
            }

            if buffer[1] & 0xC0 == 0xC0 {
                if let f = takeVariable() { return f }
                return nil
            }

            buffer.removeFirst()                // not a frame start, resync
        }
    }

    private mutating func takeVariable() -> (UInt32, [UInt8], Bool, Bool)? {
        while true {
            guard buffer.count >= 2 else { return nil }
            let t = buffer[1]
            guard t & 0xC0 == 0xC0 else { return nil }
            let isExtended = (t & 0x20) != 0
            let isRemote = (t & 0x10) != 0
            let dlc = Int(t & 0x0F)
            let idLen = isExtended ? 4 : 2
            let payloadLen = isRemote ? 0 : dlc
            let total = 2 + idLen + payloadLen + 1

            guard buffer.count >= total else { return nil }
            guard buffer[total - 1] == FrameCodec.end else {
                buffer.removeFirst()          // bad framing, resync
                return nil
            }

            var canID: UInt32 = 0
            for i in 0..<idLen { canID |= UInt32(buffer[2 + i]) << (8 * i) }
            let data = Array(buffer[(2 + idLen)..<(2 + idLen + payloadLen)])
            buffer.removeFirst(total)
            return (canID, data, isExtended, isRemote)
        }
    }

    private mutating func takeFixed() -> (UInt32, [UInt8], Bool, Bool)? {
        guard buffer.count >= 20 else { return nil }

        let body = buffer[2..<19]
        guard FrameCodec.checksum(body) == buffer[19] else {
            buffer.removeFirst()              // bad checksum, resync
            return nil
        }

        let isExtended = buffer[3] == CANFrameType.extended.rawValue
        let isRemote = buffer[4] == CANFrameFormat.remote.rawValue
        var canID: UInt32 = 0
        for i in 0..<4 { canID |= UInt32(buffer[5 + i]) << (8 * i) }
        let dlc = min(Int(buffer[9]), 8)
        let data = isRemote ? [] : Array(buffer[10..<(10 + dlc)])
        buffer.removeFirst(20)
        return (canID, data, isExtended, isRemote)
    }
}
