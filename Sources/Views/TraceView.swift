import SwiftUI
import UniformTypeIdentifiers

struct TraceView: View {
    @Environment(AppModel.self) private var model
    @State private var exportTrace = false
    @State private var chooseAutoSave = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            // Toolbar mirrors the reference application's row above the grid.
            // Every control is fixedSize so the row never compresses a label into a
            // vertical stack of letters when the pane is narrow.
            ViewThatFits(in: .horizontal) {
                toolbar(spacing: 14)
                toolbar(spacing: 8)
                ScrollView(.horizontal, showsIndicators: false) { toolbar(spacing: 10) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Table(model.frames) {
                TableColumn("No") { Text("\($0.sequence)").monospacedDigit() }
                    .width(min: 36, ideal: 44, max: 70)
                TableColumn("Direction") { f in
                    Text(f.direction.rawValue)
                        .foregroundStyle(f.direction == .send ? Color.accentColor : .primary)
                }
                .width(min: 58, ideal: 68, max: 90)
                TableColumn("Time") { Text($0.timeText).monospaced() }
                    .width(min: 76, ideal: 90, max: 120)
                TableColumn("Format") { Text($0.frameFormatText) }
                    .width(min: 74, ideal: 88, max: 120)
                TableColumn("Type") { Text($0.frameTypeText) }
                    .width(min: 80, ideal: 94, max: 130)
                TableColumn("Frame Id") { Text($0.idText).monospaced() }
                    .width(min: 76, ideal: 88, max: 120)
                TableColumn("Len") { Text("\($0.dlc)").monospacedDigit() }
                    .width(min: 30, ideal: 36, max: 50)
                TableColumn("Data(Hex)") { Text($0.dataText).monospaced() }
                    .width(min: 150, ideal: 220)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .fileExporter(
            isPresented: $exportTrace,
            document: TextDocument(text: model.traceCSV()),
            contentType: .commaSeparatedText,
            defaultFilename: "trace"
        ) { result in
            if case .failure(let e) = result {
                model.setStatus(e.localizedDescription, error: true)
            } else {
                model.setStatus("Trace saved.")
            }
        }
        .fileExporter(
            isPresented: $chooseAutoSave,
            document: TextDocument(text: ""),
            contentType: .commaSeparatedText,
            defaultFilename: "autosave"
        ) { result in
            switch result {
            case .success(let url): model.beginAutoSave(to: url)
            case .failure(let e):
                model.autoSave = false
                model.setStatus(e.localizedDescription, error: true)
            }
        }
    }

    @ViewBuilder
    private func toolbar(spacing: CGFloat) -> some View {
        @Bindable var model = model

        HStack(spacing: spacing) {
            HStack(spacing: 6) {
                Text("Total:").fixedSize()
                TextField("", text: $model.totalRowsText)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .help("Maximum rows kept in the view.")
            }
            .fixedSize()

            Toggle("Display receive only", isOn: $model.displayReceiveOnly).fixedSize()
            Toggle("Overlay display", isOn: $model.overlayDisplay)
                .fixedSize()
                .help("Collapse repeats of the same ID onto one row instead of scrolling.")
            Toggle("Pause", isOn: $model.paused).fixedSize()

            Spacer(minLength: 8)

            Button("Clear") { model.clearTrace() }.fixedSize()
            Button("Save") { exportTrace = true }.fixedSize()
            Toggle("Auto Save", isOn: Binding(
                get: { model.autoSave },
                set: { on in
                    model.autoSave = on
                    if on { chooseAutoSave = true } else { model.endAutoSave() }
                }
            ))
            .fixedSize()
        }
        .toggleStyle(.checkbox)
        .lineLimit(1)
    }
}

/// Minimal document wrapper so Save / Auto Save can use the system panel.
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let d = configuration.file.regularFileContents {
            text = String(decoding: d, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
