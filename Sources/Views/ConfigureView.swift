import SwiftUI

struct ConfigureView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {

            GroupBox("Com Configure") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Com Port:").fixedSize()
                        Picker("", selection: $model.selectedPortPath) {
                            ForEach(model.ports) { p in
                                Text(label(for: p)).tag(p.path)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Button("Find") { model.refreshPorts() }
                    }
                    GridRow {
                        Text("Baud Rate:").fixedSize()
                        Picker("", selection: $model.serialBaud) {
                            ForEach(AppModel.serialBaudChoices, id: \.self) {
                                Text("\($0)").tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(model.isOpen)
                        Button(model.isOpen ? "Close" : "Open") { model.toggleOpen() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(6)
            }

            GroupBox("CAN Configure") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("CAN Mode:")
                        Picker("", selection: $model.settings.mode) {
                            ForEach(CANMode.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                    GridRow {
                        Text("Frame Type:")
                        Picker("", selection: $model.settings.frameType) {
                            ForEach(CANFrameType.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                    GridRow {
                        Text("CAN Baud Rate:")
                        Picker("", selection: $model.settings.speed) {
                            ForEach(CANSpeed.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(model.settings.manualBitTiming)
                    }
                    GridRow {
                        Text("SYNC_SEG:")
                        Picker("", selection: $model.settings.syncJumpWidth) {
                            ForEach(SyncJumpWidth.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(!model.settings.manualBitTiming)
                    }
                    GridRow {
                        Text("BS1:")
                        Picker("", selection: $model.settings.bitSegment1) {
                            ForEach(BitSegment1.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(!model.settings.manualBitTiming)
                    }
                    GridRow {
                        Text("BS2:")
                        Picker("", selection: $model.settings.bitSegment2) {
                            ForEach(BitSegment2.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(!model.settings.manualBitTiming)
                    }
                    GridRow {
                        Text("Prescale(Dec):")
                        HStack(spacing: 8) {
                            TextField("", value: $model.settings.prescaler, format: .number)
                                .frame(width: 70)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!model.settings.manualBitTiming)
                            Text("(<1024)").foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Text(model.settings.computedBitRateText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(6)

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Manual Set Baud Rate:", isOn: $model.settings.manualBitTiming)
                        .fixedSize()
                    Toggle("Only Send once", isOn: $model.settings.sendOnce)
                        .fixedSize()
                        .help("Disables the adapter's automatic retransmission.")

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text("Filter ID(Hex) 0x:").fixedSize()
                            HexField(value: $model.settings.filterID)
                        }
                        GridRow {
                            Text("Mask ID(Hex) 0x:").fixedSize()
                            HexField(value: $model.settings.maskID)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Protocol") {
                Picker("", selection: $model.settings.wireProtocol) {
                    ForEach(WireProtocol.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(6)
            }

            HStack {
                Button("CAN Bus Status") { model.requestBusStatus() }
                    .disabled(!model.isOpen)
                Spacer()
                Button("Set and Start") { model.setAndStart() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isOpen)
            }
        }
    }

    private func label(for p: SerialPortInfo) -> String {
        if p.isUSBCANAdapter {
            return "\(p.displayName)  —  USB-CAN-A"
                + (p.looksLikeWCHDriver ? "" : "  (Apple driver!)")
        }
        return p.displayName
    }
}

/// Hex entry that keeps a UInt32 in sync with "0x" style text.
struct HexField: View {
    @Binding var value: UInt32
    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .frame(width: 120)
            .textFieldStyle(.roundedBorder)
            .monospaced()
            .onAppear { text = String(format: "%08X", value) }
            .onChange(of: text) { _, new in
                if let v = HexParsing.parseID(new) { value = v }
            }
    }
}
