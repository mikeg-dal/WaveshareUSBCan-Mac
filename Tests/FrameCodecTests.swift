import Testing
@testable import USBCAN

/// These byte layouts were recovered from the vendor's Windows application.
/// If any of these fail, the adapter will go silent with no error anywhere,
/// so treat them as a contract rather than incidental coverage.
struct FrameCodecTests {

    // MARK: - Settings

    @Test func settingsCommandIsTwentyBytesWithCorrectChecksum() {
        var s = AdapterSettings()
        s.speed = .bps250k
        s.frameType = .standard
        s.mode = .loopback

        let f = FrameCodec.settingsCommand(s)
        #expect(f.count == 20)
        #expect(f[0] == 0xAA)
        #expect(f[1] == 0x55)
        #expect(f[2] == 0x12)
        #expect(f[3] == 0x05)          // 250k
        #expect(f[4] == 0x01)          // standard
        #expect(f[13] == 0x01)         // loopback
        #expect(f[14] == 0x01)         // automatic retransmission on

        let sum = f[2...18].reduce(UInt8(0)) { $0 &+ $1 }
        #expect(f[19] == sum)
    }

    /// Matches the known-good frame the Python implementation sends for
    /// 250 kbps / standard / loopback.
    @Test func settingsCommandMatchesReferenceBytes() {
        var s = AdapterSettings()
        s.speed = .bps250k
        s.frameType = .standard
        s.mode = .loopback
        let expected: [UInt8] = [
            0xAA, 0x55, 0x12, 0x05, 0x01, 0, 0, 0, 0, 0, 0, 0, 0,
            0x01, 0x01, 0, 0, 0, 0, 0x1A,
        ]
        #expect(FrameCodec.settingsCommand(s) == expected)
    }

    @Test func sendOnceDisablesAutomaticRetransmission() {
        var s = AdapterSettings()
        s.sendOnce = true
        #expect(FrameCodec.settingsCommand(s)[14] == 0x00)
    }

    // MARK: - Variable length frames

    @Test func variableStandardFrameLayout() {
        let f = FrameCodec.variableDataFrame(
            canID: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF],
            type: .standard, format: .data
        )
        #expect(f == [0xAA, 0xC4, 0x23, 0x01, 0xDE, 0xAD, 0xBE, 0xEF, 0x55])
        #expect(f.count == 4 + 5)
    }

    @Test func variableExtendedFrameSetsBit5AndUsesFourIdBytes() {
        let f = FrameCodec.variableDataFrame(
            canID: 0x0001_2345, data: [0x01, 0x02],
            type: .extended, format: .data
        )
        #expect(f[0] == 0xAA)
        #expect(f[1] == 0xE2)                      // 0xC0 | 0x20 | dlc 2
        #expect(Array(f[2..<6]) == [0x45, 0x23, 0x01, 0x00])   // LSB first
        #expect(f.last == 0x55)
        #expect(f.count == 2 + 7)
    }

    @Test func variableRemoteFrameSetsBit4AndCarriesNoData() {
        let f = FrameCodec.variableDataFrame(
            canID: 0x100, data: [0xFF], type: .standard, format: .remote
        )
        #expect(f[1] & 0x10 == 0x10)
        #expect(f == [0xAA, f[1], 0x00, 0x01, 0x55])
    }

    // MARK: - Fixed 20-byte frames

    @Test func fixedFrameLayoutAndChecksum() {
        let f = FrameCodec.fixedDataFrame(
            canID: 0x00, data: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77],
            type: .standard, format: .data
        )
        #expect(f.count == 20)
        #expect(Array(f[0..<5]) == [0xAA, 0x55, 0x01, 0x01, 0x01])
        #expect(Array(f[5..<9]) == [0, 0, 0, 0])   // ID little endian
        #expect(f[9] == 8)                          // DLC
        #expect(Array(f[10..<18]) == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
        #expect(f[18] == 0)                         // reserved

        let sum = f[2...18].reduce(UInt8(0)) { $0 &+ $1 }
        #expect(f[19] == sum)
    }

    @Test func fixedFrameZeroPadsShortPayloads() {
        let f = FrameCodec.fixedDataFrame(
            canID: 0x7FF, data: [0xAB], type: .standard, format: .data
        )
        #expect(f[9] == 1)
        #expect(f[10] == 0xAB)
        #expect(Array(f[11..<18]) == [UInt8](repeating: 0, count: 7))
    }

    // MARK: - Receive filter

    @Test func receiveFilterEmptyListIsFiveBytes() {
        let f = FrameCodec.receiveFilterCommand(ids: [], mode: .dontUpload)
        #expect(f == [0xAA, 0x55, 0x11, 0x00, 0x11])
    }

    @Test func receiveFilterEncodesIdsLittleEndian() {
        let f = FrameCodec.receiveFilterCommand(ids: [0x01, 0x02], mode: .uploadOnly)
        #expect(f[2] == 0x11)
        #expect(f[3] == 2)
        #expect(Array(f[4..<8]) == [0x01, 0, 0, 0])
        #expect(Array(f[8..<12]) == [0x02, 0, 0, 0])
        let sum = f[2..<(f.count - 1)].reduce(UInt8(0)) { $0 &+ $1 }
        #expect(f.last == sum)
    }

    @Test func receiveFilterAllUploadedUsesCommand0x10() {
        let f = FrameCodec.receiveFilterCommand(ids: [0x05], mode: .allUploaded)
        #expect(f[2] == 0x10)
    }

    @Test func receiveFilterCapsAtFifty() {
        let ids = (0..<80).map { UInt32($0) }
        let f = FrameCodec.receiveFilterCommand(ids: ids, mode: .uploadOnly)
        #expect(f[3] == 50)
    }

    // MARK: - Decoding

    @Test func decoderRoundTripsVariableFrames() {
        var d = FrameDecoder(wire: .variable)
        d.append(FrameCodec.variableDataFrame(
            canID: 0x123, data: [0xDE, 0xAD], type: .standard, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x123)
        #expect(out[0].data == [0xDE, 0xAD])
        #expect(out[0].isExtended == false)
    }

    @Test func decoderRoundTripsFixedFrames() {
        var d = FrameDecoder(wire: .fixed20)
        d.append(FrameCodec.fixedDataFrame(
            canID: 0x1AB, data: [1, 2, 3], type: .extended, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x1AB)
        #expect(out[0].data == [1, 2, 3])
        #expect(out[0].isExtended == true)
    }

    /// A payload byte may itself be 0x55, so length must come from the type byte
    /// rather than from scanning for the terminator.
    @Test func decoderHandlesPayloadContainingTerminatorByte() {
        var d = FrameDecoder(wire: .variable)
        d.append(FrameCodec.variableDataFrame(
            canID: 0x1, data: [0x55, 0x55, 0x55], type: .standard, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].data == [0x55, 0x55, 0x55])
    }

    @Test func decoderReassemblesFramesSplitAcrossReads() {
        let frame = FrameCodec.variableDataFrame(
            canID: 0x321, data: [9, 8, 7], type: .standard, format: .data)
        var d = FrameDecoder(wire: .variable)
        d.append(Array(frame[0..<3]))
        #expect(d.drain().isEmpty)
        d.append(Array(frame[3...]))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x321)
    }

    @Test func decoderResynchronisesAfterGarbage() {
        var d = FrameDecoder(wire: .variable)
        d.append([0x00, 0xFF, 0x12])
        d.append(FrameCodec.variableDataFrame(
            canID: 0x7FF, data: [0x01], type: .standard, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x7FF)
    }

    /// Regression: the adapter answers in variable-length framing after the 0x12
    /// settings command even when the host sends fixed 20-byte frames. A decoder
    /// pinned to the configured mode drops every reply, which is indistinguishable
    /// from an adapter that never responds. Observed against real hardware.
    @Test func decoderAcceptsVariableReplyWhileConfiguredForFixed() {
        var d = FrameDecoder(wire: .fixed20)
        d.append([0xAA, 0xC4, 0x23, 0x01, 0xDE, 0xAD, 0xBE, 0xEF, 0x55])
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x123)
        #expect(out[0].data == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func decoderAcceptsFixedReplyWhileConfiguredForVariable() {
        var d = FrameDecoder(wire: .variable)
        d.append(FrameCodec.fixedDataFrame(
            canID: 0x55, data: [0x55], type: .standard, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x55)
    }

    /// A command echo such as AA 55 11 00 11 must not stall the stream while the
    /// decoder waits for 20 bytes that will never arrive.
    @Test func decoderSkipsCommandEchoAndStillFindsNextFrame() {
        var d = FrameDecoder(wire: .variable)
        d.append([0xAA, 0x55, 0x11, 0x00, 0x11])
        d.append(FrameCodec.variableDataFrame(
            canID: 0x201, data: [0x07], type: .standard, format: .data))
        let out = d.drain()
        #expect(out.count == 1)
        #expect(out[0].canID == 0x201)
    }

    @Test func decoderRejectsFixedFrameWithBadChecksum() {
        var bad = FrameCodec.fixedDataFrame(
            canID: 0x10, data: [1], type: .standard, format: .data)
        bad[19] = bad[19] &+ 1
        var d = FrameDecoder(wire: .fixed20)
        d.append(bad)
        #expect(d.drain().isEmpty)
    }

    // MARK: - Parsing helpers

    @Test func hexIdParsingAcceptsPrefixedAndBare() {
        #expect(HexParsing.parseID("0x123") == 0x123)
        #expect(HexParsing.parseID("123") == 0x123)
        #expect(HexParsing.parseID("  0X1aB ") == 0x1AB)
        #expect(HexParsing.parseID("") == nil)
        #expect(HexParsing.parseID("zz") == nil)
    }

    @Test func hexDataParsingAcceptsSpacedAndPacked() {
        #expect(HexParsing.parseData("00 11 22") == [0x00, 0x11, 0x22])
        #expect(HexParsing.parseData("001122") == [0x00, 0x11, 0x22])
        #expect(HexParsing.parseData("") == [])
        #expect(HexParsing.parseData("0 1 2") == nil)
    }

    // MARK: - Bit timing

    @Test func computedBitRateMatchesPanelValues() {
        var s = AdapterSettings()
        s.syncJumpWidth = .tq1
        s.bitSegment1 = .tq6
        s.bitSegment2 = .tq5
        s.prescaler = 12
        // 36 MHz / 12 / (1 + 6 + 5) = 250000
        #expect(abs(s.computedBitRate - 250_000) < 0.5)
    }
}
