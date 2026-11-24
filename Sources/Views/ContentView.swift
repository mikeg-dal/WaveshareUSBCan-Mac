import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HSplitView {
                TraceView()
                    .frame(minWidth: 560, idealWidth: 840)

                ScrollView {
                    VStack(spacing: 10) {
                        Panel("Must be Configured", initiallyExpanded: true) { ConfigureView() }
                        Panel("Manually Send") { ManualSendView() }
                        Panel("Automatically Send") { AutoSendView() }
                        Panel("Auto Reply") { AutoReplyView() }
                        Panel("Special Features") { SpecialFeaturesView() }
                        Panel("Help") { HelpView() }
                    }
                    .padding(12)
                }
                .frame(minWidth: 400, idealWidth: 450, maxWidth: 620)
            }

            Divider()
            StatusBar()
        }
    }
}

/// A collapsible section, standing in for the Windows app's QToolBox pages.
struct Panel<Content: View>: View {
    let title: String
    @State private var expanded: Bool
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._expanded = State(initialValue: initiallyExpanded)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content()
                .padding(.top, 8)
        } label: {
            Text(title)
                .font(.headline)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isOpen ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(model.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(model.statusIsError ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if !model.busStatusText.isEmpty {
                Text(model.busStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
    }
}
