import SwiftUI

struct URLInputView: View {
    @EnvironmentObject var main: MainViewModel
    @FocusState private var focused: Bool

    var body: some View {
        GlassCard {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Paste or drop a video link", text: $main.urlText)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { main.analyze(userInitiated: true) }
                    if !main.urlText.isEmpty {
                        Button { main.reset() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.05)))

                Button { main.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(PillButtonStyle())

                Button { main.analyze(userInitiated: true) } label: {
                    if main.isAnalyzing { ProgressView().controlSize(.small).frame(width: 52) }
                    else { Text("Analyze") }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(main.urlText.trimmingCharacters(in: .whitespaces).isEmpty || main.isAnalyzing)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: JuktoConstants.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .opacity(main.isDropTargeted ? 1 : 0)
        }
        .animation(JuktoAnimation.pill, value: main.isDropTargeted)
        .onDrop(of: [.url, .plainText], isTargeted: $main.isDropTargeted) { main.handleDrop($0) }
    }
}
