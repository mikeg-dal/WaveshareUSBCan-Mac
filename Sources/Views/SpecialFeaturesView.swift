import SwiftUI

struct SpecialFeaturesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<ReceiveIDRow.ID>()
    @State private var exporting = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {

            GroupBox("Change the baud rate of the adapter") {
                HStack {
                    Picker("", selection: $model.changeBaudSelection) {
                        ForEach(CANSpeed.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Button("Change") { model.changeAdapterBaud() }
                        .disabled(!model.isOpen)
                    Spacer()
                }
                .padding(6)
            }

            GroupBox("Configure the receive ID") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Remove") {
                            model.receiveIDRows.removeAll { selection.contains($0.id) }
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)
                        Button("Insert") {
                            guard model.receiveIDRows.count < FrameCodec.maxReceiveFilterIDs else {
                                model.setStatus(
                                    "The number of receive ID tables cannot exceed "
                                        + "\(FrameCodec.maxReceiveFilterIDs).", error: true)
                                return
                            }
                            model.receiveIDRows.append(ReceiveIDRow())
                        }
                        Spacer()
                        Button("Save") { exporting = true }
                    }

                    Picker("", selection: $model.receiveUploadMode) {
                        ForEach(ReceiveUploadMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    ForEach($model.receiveIDRows) { $row in
                        TextField("Receive Id(Hex)", text: $row.idHex)
                            .textFieldStyle(.roundedBorder)
                            .monospaced()
                            .frame(width: 140)
                    }

                    HStack {
                        Text("\(model.receiveIDRows.count) / \(FrameCodec.maxReceiveFilterIDs) IDs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Set") { model.applyReceiveFilter() }
                            .disabled(!model.isOpen)
                    }
                }
                .padding(6)
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: TextDocument(text: RowFiles.encodeReceiveIDs(model.receiveIDRows)),
            contentType: .plainText,
            defaultFilename: "receiveID"
        ) { _ in }
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("How to use") {
                    """
                    1. Press Find, then pick the USB-CAN-A and press Open.
                    2. Set CAN Mode, Frame Type and CAN Baud Rate, choose a Protocol, \
                    then press Set and Start. Nothing is sent to the adapter until you do.
                    3. Send frames from Manually Send, or drive them from Automatically Send.

                    Loop back mode echoes frames inside the adapter without touching the bus, \
                    so it is the safest way to prove the link works with nothing attached.
                    """
                }

                section("Main problems and Solutions") {
                    """
                    Nothing is received, and nothing reports an error.

                    On macOS this is almost always the driver. This adapter runs its serial \
                    link at 2,000,000 baud. Apple's built-in CH340 driver mis-programs the \
                    divisor at that rate and delivers roughly half of it, so the adapter \
                    receives a corrupted bit stream and never answers. No error is raised \
                    anywhere — it looks exactly like dead hardware.

                    Install WCH's CH34xVCPDriver, then unplug and replug the adapter. The \
                    port is named /dev/cu.wchusbserial* when WCH's driver owns it, and \
                    /dev/cu.usbserial* when Apple's does. This app warns you in the port \
                    list when it sees the Apple name.

                    Lowering the baud rate does not help, because the adapter speaks only \
                    2,000,000 baud.
                    """
                }

                section("Checking which driver is active") {
                    """
                    systemextensionsctl list

                    Look for: cn.wch.CH34xVCPDriver  [activated enabled]
                    """
                }
            }
            .padding(4)
        }
        .frame(maxHeight: 380)
    }

    private func section(_ title: String, _ body: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
