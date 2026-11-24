import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {

    // MARK: - Connection

    var ports: [SerialPortInfo] = []
    var selectedPortPath: String = ""
    var serialBaud: Int = 2_000_000
    var isOpen: Bool = false
    var isConfigured: Bool = false

    static let serialBaudChoices = [
        9_600, 19_200, 38_400, 57_600, 115_200, 230_400,
        460_800, 921_600, 1_000_000, 2_000_000,
    ]

    // MARK: - Adapter settings

    var settings = AdapterSettings()

    // MARK: - Trace view

    var frames: [CANFrame] = []
    var totalRowsText: String = "1000"
    var displayReceiveOnly = false
    var overlayDisplay = false
    var paused = false
    var autoSave = false

    private var sequence = 0
    private var overlayIndex: [String: Int] = [:]

    var totalRows: Int { max(1, Int(totalRowsText) ?? 1000) }

    // MARK: - Panels

    var manualRows: [ManualSendRow] = (0..<10).map {
        ManualSendRow(idHex: HexParsing.formatID(UInt32($0)))
    }
    var autoRows: [AutoSendRow] = [AutoSendRow()]
    var replyRows: [AutoReplyRow] = [AutoReplyRow()]
    var receiveIDRows: [ReceiveIDRow] = [ReceiveIDRow()]

    var autoReplyEnabled = false
    var autoCycle = false
    var isAutoSending = false
    var receiveUploadMode: ReceiveUploadMode = .allUploaded
    var changeBaudSelection: CANSpeed = .bps250k

    // MARK: - Status

    var statusMessage: String = "Ready."
    var statusIsError = false
    var busStatusText: String = ""

    // MARK: - Internals

    private let port = SerialPort()
    private var decoder = FrameDecoder(wire: .fixed20)
    private var autoSendTask: Task<Void, Never>?
    private var autoSaveHandle: FileHandle?

    init() {
        refreshPorts()
    }

    // MARK: - Ports

    func refreshPorts() {
        ports = PortScanner.scan()
        if selectedPortPath.isEmpty || !ports.contains(where: { $0.path == selectedPortPath }) {
            selectedPortPath = ports.first(where: \.isUSBCANAdapter)?.path
                ?? ports.first?.path
                ?? ""
        }
        let adapters = ports.filter(\.isUSBCANAdapter)
        if adapters.isEmpty {
            setStatus("No USB-CAN-A found. Check the cable, or press Find again.", error: true)
        } else if let a = adapters.first, !a.looksLikeWCHDriver {
            setStatus(
                "Adapter found on Apple's driver (\(a.displayName)). 2 Mbaud will not work — "
                    + "install WCH's CH34xVCPDriver. See Help.",
                error: true
            )
        } else {
            setStatus("Found \(adapters.count) adapter(s).")
        }
    }

    // MARK: - Open / close

    func toggleOpen() {
        isOpen ? closePort() : openPort()
    }

    func openPort() {
        guard !selectedPortPath.isEmpty else {
            setStatus("Select a COM port first.", error: true)
            return
        }
        do {
            decoder = FrameDecoder(wire: settings.wireProtocol)
            try port.open(path: selectedPortPath, baud: serialBaud, stopBits: 2) { [weak self] bytes in
                Task { @MainActor in self?.ingest(bytes) }
            }
            isOpen = true
            isConfigured = false
            setStatus("COM Open OK")
        } catch {
            isOpen = false
            setStatus(error.localizedDescription, error: true)
        }
    }

    func closePort() {
        stopAutoSend()
        port.close()
        isOpen = false
        isConfigured = false
        setStatus("COM close OK")
    }

    // MARK: - Configure

    /// "Set and Start" — pushes the settings command to the adapter.
    func setAndStart() {
        guard requireOpen() else { return }
        decoder = FrameDecoder(wire: settings.wireProtocol)
        do {
            try port.write(FrameCodec.settingsCommand(settings))
            isConfigured = true
            setStatus("Configured: \(settings.mode.label), \(settings.speed.label), "
                      + "\(settings.wireProtocol.label).")
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    /// Queries the adapter's CAN controller state.
    ///
    /// NOTE: the request byte for this command has not been confirmed against the
    /// vendor binary, so the adapter may not answer. The reply parsing below matches
    /// the vendor application's own wording. See README "Known gaps".
    func requestBusStatus() {
        guard requireOpen() else { return }
        let body: [UInt8] = [0x04, 0x00]
        var frame: [UInt8] = [FrameCodec.start, FrameCodec.end]
        frame.append(contentsOf: body)
        frame.append(FrameCodec.checksum(body[body.startIndex...]))
        do {
            try port.write(frame)
            setStatus("CAN Bus Status requested.")
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    /// "Change the baud rate of the adapter" (Special Features).
    func changeAdapterBaud() {
        guard requireOpen() else { return }
        var s = settings
        s.speed = changeBaudSelection
        do {
            try port.write(FrameCodec.settingsCommand(s))
            settings.speed = changeBaudSelection
            setStatus("Adapter bit rate set to \(changeBaudSelection.label).")
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    /// "Configure the receive ID" (Special Features).
    func applyReceiveFilter() {
        guard requireOpen() else { return }
        let ids = receiveIDRows.compactMap { HexParsing.parseID($0.idHex) }
        guard receiveUploadMode == .dontUpload || !ids.isEmpty else {
            setStatus("There is no ID data in items, please check", error: true)
            return
        }
        guard ids.count <= FrameCodec.maxReceiveFilterIDs else {
            setStatus("The number of receive ID tables cannot exceed "
                      + "\(FrameCodec.maxReceiveFilterIDs).", error: true)
            return
        }
        do {
            try port.write(FrameCodec.receiveFilterCommand(ids: ids, mode: receiveUploadMode))
            setStatus("Receive filter set (\(receiveUploadMode.rawValue), \(ids.count) ID(s)).")
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    // MARK: - Sending

    @discardableResult
    func send(idHex: String, dataHex: String) -> Bool {
        guard requireOpen() else { return false }
        guard let canID = HexParsing.parseID(idHex) else {
            setStatus("ID can not be empty", error: true)
            return false
        }
        guard let data = HexParsing.parseData(dataHex) else {
            setStatus("Data must be hex bytes, for example 00 11 22 33.", error: true)
            return false
        }
        let frame = FrameCodec.dataFrame(
            canID: canID,
            data: data,
            type: settings.frameType,
            format: .data,
            wire: settings.wireProtocol
        )
        do {
            try port.write(frame)
            record(
                CANFrame(
                    sequence: 0, direction: .send, timestamp: Date(),
                    isExtended: settings.frameType.isExtended, isRemote: false,
                    canID: canID, data: Array(data.prefix(8))
                )
            )
            return true
        } catch {
            setStatus(error.localizedDescription, error: true)
            return false
        }
    }

    func sendManualRow(_ row: ManualSendRow) {
        send(idHex: row.idHex, dataHex: row.dataHex)
    }

    /// "Send in sequence" — walks the enabled auto rows, honouring each interval,
    /// repeating while Cycle is on.
    func startAutoSend() {
        guard requireOpen() else { return }
        let rows = autoRows.filter(\.enabled)
        guard !rows.isEmpty else {
            setStatus("Please check that there is no data to send", error: true)
            return
        }
        for r in rows {
            guard let ms = Int(r.intervalMs.trimmingCharacters(in: .whitespaces)) else {
                setStatus(r.intervalMs.isEmpty
                          ? "Sending interval cannot be empty"
                          : "Error in sending interval value", error: true)
                return
            }
            guard ms >= 0 else {
                setStatus("Error in sending interval value", error: true)
                return
            }
        }

        isAutoSending = true
        setStatus("Automatic sending started.")
        autoSendTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                for r in rows {
                    if Task.isCancelled { return }
                    let ok = self.send(idHex: r.idHex, dataHex: r.dataHex)
                    if !ok { self.stopAutoSend(); return }
                    let ms = Int(r.intervalMs) ?? 0
                    try? await Task.sleep(for: .milliseconds(ms))
                }
            } while self.autoCycle && !Task.isCancelled
            self.stopAutoSend()
        }
    }

    func stopAutoSend() {
        autoSendTask?.cancel()
        autoSendTask = nil
        if isAutoSending {
            isAutoSending = false
            setStatus("Automatic sending stopped.")
        }
    }

    // MARK: - Receiving

    private func ingest(_ bytes: [UInt8]) {
        decoder.append(bytes)
        for f in decoder.drain() {
            let frame = CANFrame(
                sequence: 0, direction: .received, timestamp: Date(),
                isExtended: f.isExtended, isRemote: f.isRemote,
                canID: f.canID, data: f.data
            )
            record(frame)
            if autoReplyEnabled { respondIfNeeded(to: frame) }
        }
    }

    private func respondIfNeeded(to frame: CANFrame) {
        for row in replyRows where HexParsing.parseID(row.receiveIdHex) == frame.canID {
            send(idHex: row.replyIdHex, dataHex: row.replyDataHex)
        }
    }

    private func record(_ frame: CANFrame) {
        guard !paused else { return }
        if displayReceiveOnly && frame.direction == .send { return }

        var f = frame
        sequence += 1
        f.sequence = sequence

        if overlayDisplay {
            if let existing = overlayIndex[f.overlayKey], existing < frames.count {
                frames[existing] = f
            } else {
                frames.append(f)
                overlayIndex[f.overlayKey] = frames.count - 1
            }
        } else {
            frames.append(f)
        }

        if frames.count > totalRows {
            frames.removeFirst(frames.count - totalRows)
            rebuildOverlayIndex()
        }
        if autoSave { appendAutoSave(f) }
    }

    private func rebuildOverlayIndex() {
        guard overlayDisplay else { return }
        overlayIndex.removeAll(keepingCapacity: true)
        for (i, f) in frames.enumerated() { overlayIndex[f.overlayKey] = i }
    }

    func clearTrace() {
        frames.removeAll()
        overlayIndex.removeAll()
        sequence = 0
        setStatus("Cleared.")
    }

    // MARK: - Saving

    func traceCSV() -> String {
        var out = "No,Direction,Time,Frame Format,Frame Type,Frame Id,Data Length,Data(Hex)\n"
        for f in frames {
            out += "\(f.sequence),\(f.direction.rawValue),\(f.timeText),"
                + "\(f.frameFormatText),\(f.frameTypeText),\(f.idText),\(f.dlc),\(f.dataText)\n"
        }
        return out
    }

    private func appendAutoSave(_ f: CANFrame) {
        guard let handle = autoSaveHandle else { return }
        let line = "\(f.sequence),\(f.direction.rawValue),\(f.timeText),"
            + "\(f.frameFormatText),\(f.frameTypeText),\(f.idText),\(f.dlc),\(f.dataText)\n"
        if let d = line.data(using: .utf8) { try? handle.write(contentsOf: d) }
    }

    func beginAutoSave(to url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        autoSaveHandle = try? FileHandle(forWritingTo: url)
        let header = "No,Direction,Time,Frame Format,Frame Type,Frame Id,Data Length,Data(Hex)\n"
        if let d = header.data(using: .utf8) { try? autoSaveHandle?.write(contentsOf: d) }
        setStatus("Auto Save to \(url.lastPathComponent).")
    }

    func endAutoSave() {
        try? autoSaveHandle?.close()
        autoSaveHandle = nil
    }

    // MARK: - Helpers

    private func requireOpen() -> Bool {
        if !isOpen {
            setStatus("The COM port is closed, please open the COM port first", error: true)
            return false
        }
        return true
    }

    func setStatus(_ text: String, error: Bool = false) {
        statusMessage = text
        statusIsError = error
    }
}
