import Foundation

/// A row in the "Manually Send" table.
struct ManualSendRow: Identifiable, Hashable, Sendable {
    var id = UUID()
    var idHex: String = "0x00000000"
    var dataHex: String = "00 11 22 33 44 55 66 77"
}

/// A row in the "Automatically Send" table.
struct AutoSendRow: Identifiable, Hashable, Sendable {
    var id = UUID()
    var idHex: String = "0x00000000"
    var dataHex: String = "00 11 22 33 44 55 66 77"
    var intervalMs: String = "1000"
    var enabled: Bool = false
}

/// A row in the "Auto Reply" table: when `receiveIdHex` arrives, send the reply.
struct AutoReplyRow: Identifiable, Hashable, Sendable {
    var id = UUID()
    var receiveIdHex: String = "0x00000000"
    var replyIdHex: String = "0x00000001"
    var replyDataHex: String = "00 11 22 33 44 55 66 77"
}

/// A row in "Configure the receive ID".
struct ReceiveIDRow: Identifiable, Hashable, Sendable {
    var id = UUID()
    var idHex: String = "0x00000000"
}

enum HexParsing {
    /// Accepts "0x123", "123", "0X123" and surrounding whitespace.
    static func parseID(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("0x") { t = String(t.dropFirst(2)) }
        guard !t.isEmpty else { return nil }
        return UInt32(t, radix: 16)
    }

    static func parseData(_ s: String) -> [UInt8]? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [] }
        return [UInt8].fromHexString(t)
    }

    static func formatID(_ v: UInt32) -> String { "0x" + String(format: "%08X", v) }
}

/// Tab-free CSV used by the reference application's Save buttons, so files written
/// here stay interchangeable with manual.txt / auto.txt / reply.txt / receiveID.txt.
enum RowFiles {
    static func encodeManual(_ rows: [ManualSendRow]) -> String {
        rows.map { "\($0.idHex),\($0.dataHex),Send" }.joined(separator: "\n") + "\n"
    }

    static func decodeManual(_ text: String) -> [ManualSendRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            return ManualSendRow(
                idHex: String(parts[0]).trimmingCharacters(in: .whitespaces),
                dataHex: String(parts[1]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static func encodeAuto(_ rows: [AutoSendRow]) -> String {
        rows.map { "\($0.idHex),\($0.dataHex),\($0.intervalMs),\($0.enabled)" }
            .joined(separator: "\n") + "\n"
    }

    static func decodeAuto(_ text: String) -> [AutoSendRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let p = line.split(separator: ",", omittingEmptySubsequences: false)
            guard p.count >= 3 else { return nil }
            return AutoSendRow(
                idHex: String(p[0]).trimmingCharacters(in: .whitespaces),
                dataHex: String(p[1]).trimmingCharacters(in: .whitespaces),
                intervalMs: String(p[2]).trimmingCharacters(in: .whitespaces),
                enabled: p.count > 3 && String(p[3]).trimmingCharacters(in: .whitespaces) == "true"
            )
        }
    }

    static func encodeReply(_ rows: [AutoReplyRow]) -> String {
        rows.map { "\($0.receiveIdHex),\($0.replyIdHex),\($0.replyDataHex)" }
            .joined(separator: "\n") + "\n"
    }

    static func decodeReply(_ text: String) -> [AutoReplyRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let p = line.split(separator: ",", omittingEmptySubsequences: false)
            guard p.count >= 3 else { return nil }
            return AutoReplyRow(
                receiveIdHex: String(p[0]).trimmingCharacters(in: .whitespaces),
                replyIdHex: String(p[1]).trimmingCharacters(in: .whitespaces),
                replyDataHex: String(p[2]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static func encodeReceiveIDs(_ rows: [ReceiveIDRow]) -> String {
        rows.map(\.idHex).joined(separator: "\n") + "\n"
    }

    static func decodeReceiveIDs(_ text: String) -> [ReceiveIDRow] {
        text.split(whereSeparator: \.isNewline).map {
            ReceiveIDRow(idHex: String($0).trimmingCharacters(in: .whitespaces))
        }
    }
}
