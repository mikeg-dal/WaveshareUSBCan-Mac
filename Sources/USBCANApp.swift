import SwiftUI

@main
struct USBCANApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("USBCAN") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Adapter") {
                Button("Find Ports") { model.refreshPorts() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(model.isOpen ? "Close Port" : "Open Port") { model.toggleOpen() }
                    .keyboardShortcut("o", modifiers: [.command])
                Divider()
                Button("Set and Start") { model.setAndStart() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.isOpen)
                Button("CAN Bus Status") { model.requestBusStatus() }
                    .disabled(!model.isOpen)
                Divider()
                Button("Clear Trace") { model.clearTrace() }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
