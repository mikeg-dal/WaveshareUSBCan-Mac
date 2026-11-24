import SwiftUI

struct ManualSendView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<ManualSendRow.ID>()
    @State private var exporting = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Remove") {
                    model.manualRows.removeAll { selection.contains($0.id) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("Insert") { model.manualRows.append(ManualSendRow()) }
                Spacer()
                Button("Save") { exporting = true }
            }

            ForEach($model.manualRows) { $row in
                HStack(spacing: 8) {
                    TextField("Id(Hex)", text: $row.idHex)
                        .frame(width: 110)
                        .monospaced()
                    TextField("Data(Hex)", text: $row.dataHex)
                        .monospaced()
                    Button("Send") { model.sendManualRow(row) }
                        .disabled(!model.isOpen)
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: TextDocument(text: RowFiles.encodeManual(model.manualRows)),
            contentType: .plainText,
            defaultFilename: "manual"
        ) { _ in }
    }
}

struct AutoSendView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<AutoSendRow.ID>()
    @State private var exporting = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Remove") {
                    model.autoRows.removeAll { selection.contains($0.id) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("Insert") { model.autoRows.append(AutoSendRow()) }
                Spacer()
                Button("Save") { exporting = true }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Id(Hex)").font(.caption).foregroundStyle(.secondary)
                    Text("Data(Hex)").font(.caption).foregroundStyle(.secondary)
                    Text("Interval(ms)").font(.caption).foregroundStyle(.secondary)
                    Text("Enable").font(.caption).foregroundStyle(.secondary)
                }
                ForEach($model.autoRows) { $row in
                    GridRow {
                        TextField("", text: $row.idHex).frame(width: 100).monospaced()
                        TextField("", text: $row.dataHex).monospaced()
                        TextField("", text: $row.intervalMs).frame(width: 72).monospacedDigit()
                        Toggle("", isOn: $row.enabled).labelsHidden()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Toggle("Cycle", isOn: $model.autoCycle).toggleStyle(.checkbox)
                Spacer()
                Button("Send in sequence") { model.startAutoSend() }
                    .disabled(!model.isOpen || model.isAutoSending)
                Button("Stop") { model.stopAutoSend() }
                    .disabled(!model.isAutoSending)
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: TextDocument(text: RowFiles.encodeAuto(model.autoRows)),
            contentType: .plainText,
            defaultFilename: "auto"
        ) { _ in }
    }
}

struct AutoReplyView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<AutoReplyRow.ID>()
    @State private var exporting = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Remove") {
                    model.replyRows.removeAll { selection.contains($0.id) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("Insert") { model.replyRows.append(AutoReplyRow()) }
                Spacer()
                Toggle("Reply", isOn: $model.autoReplyEnabled).toggleStyle(.checkbox)
                Button("Save") { exporting = true }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Receive Id(Hex)").font(.caption).foregroundStyle(.secondary)
                    Text("Reply Id(Hex)").font(.caption).foregroundStyle(.secondary)
                    Text("Reply Data(Hex)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach($model.replyRows) { $row in
                    GridRow {
                        TextField("", text: $row.receiveIdHex).frame(width: 100).monospaced()
                        TextField("", text: $row.replyIdHex).frame(width: 100).monospaced()
                        TextField("", text: $row.replyDataHex).monospaced()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)

            Text("When a frame with a matching Receive Id arrives, the reply is sent automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileExporter(
            isPresented: $exporting,
            document: TextDocument(text: RowFiles.encodeReply(model.replyRows)),
            contentType: .plainText,
            defaultFilename: "reply"
        ) { _ in }
    }
}
