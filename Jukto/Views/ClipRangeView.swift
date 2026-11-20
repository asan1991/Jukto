import SwiftUI

/// Type a time like 1:23 or 83.5, or press Return / click away to apply it.
struct TimecodeField: View {
    let title: String
    let value: Double
    var onCommit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            TextField("0:00", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 76)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(focused ? 0.1 : 0.05)))
                .focused($focused)
                .onSubmit { commit() }
        }
        .onAppear { text = value.preciseTimecode }
        .onChange(of: value) { _, new in if !focused { text = new.preciseTimecode } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if let v = Self.parse(text) { onCommit(v) }
        text = value.preciseTimecode
        DispatchQueue.main.async { text = value.preciseTimecode }
    }

    static func parse(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for p in parts {
            guard let v = Double(p.replacingOccurrences(of: ",", with: ".")), v >= 0 else { return nil }
            total = total * 60 + v
        }
        return total
    }
}

struct ClipRangeView: View {
    @Binding var start: Double
    @Binding var end: Double
    let duration: Double
    @State private var dragging = false
    private let handle: CGFloat = 20
    private let space = "clipbar"

    var body: some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack(alignment: .bottom) {
                    TimecodeField(title: "Start", value: start) { v in
                        start = min(max(0, v), end - JuktoConstants.minClipLength)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Length").font(.caption2).foregroundStyle(.tertiary)
                        Text((end - start).preciseTimecode)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced)).padding(.vertical, 4)
                    }
                    Spacer()
                    TimecodeField(title: "End", value: end) { v in
                        end = max(min(duration, v), start + JuktoConstants.minClipLength)
                    }
                }
                GeometryReader { geo in
                    let usable = max(1, geo.size.width - handle)
                    let sx = CGFloat(start / duration) * usable
                    let ex = CGFloat(end / duration) * usable
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous).fill(Color.primary.opacity(0.07)).frame(height: 8)
                        Capsule(style: .continuous).fill(Color.accentColor.opacity(0.4))
                            .frame(width: max(0, ex - sx), height: 8)
                            .offset(x: sx + handle / 2)
                        knob.offset(x: sx).gesture(dragGesture(usable: usable, isStart: true))
                        knob.offset(x: ex).gesture(dragGesture(usable: usable, isStart: false))
                    }
                    .frame(maxHeight: .infinity)
                    .coordinateSpace(name: space)
                    .animation(dragging ? nil : JuktoAnimation.range, value: start)
                    .animation(dragging ? nil : JuktoAnimation.range, value: end)
                }
                .frame(height: 28)
            }
        }
    }

    private var knob: some View {
        Circle().fill(Color.accentColor)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .frame(width: handle, height: handle)
    }

    private func dragGesture(usable: CGFloat, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { v in
                dragging = true
                let t = Double((v.location.x - handle / 2) / usable) * duration
                if isStart { start = min(max(0, t), end - JuktoConstants.minClipLength) }
                else { end = max(min(duration, t), start + JuktoConstants.minClipLength) }
            }
            .onEnded { _ in dragging = false }
    }
}
