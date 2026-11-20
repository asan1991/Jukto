import SwiftUI

/// Small centered banner that disappears on its own. Used for "Copied to clipboard."
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String?
    private var token = UUID()

    func show(_ text: String, seconds: Double = 1) {
        message = text
        let mine = UUID(); token = mine
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if token == mine { message = nil }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject var center = ToastCenter.shared
    var body: some View {
        VStack {
            Spacer()
            if let m = center.message {
                Text(m)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thickMaterial, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 28)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.message)
        .allowsHitTesting(false)
    }
}
