import SwiftUI
import AppKit

// MARK: - Tokens
extension Color {
    static let juktoLavender = Color("JuktoLavender")
    static let juktoRosewood = Color("JuktoRosewood")
    static let juktoCoral    = Color("JuktoCoral")
    static let juktoBronze   = Color("JuktoBronze")
    static let juktoSuccess  = Color("JuktoSuccess")
}

enum JuktoAnimation {
    static let pill  = Animation.easeInOut(duration: 0.2)
    static let range = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let tab   = Animation.easeInOut(duration: 0.2)
}

// MARK: - Glass card
struct GlassCard<Content: View>: View {
    var radius: CGFloat
    var padding: CGFloat
    let content: Content

    init(radius: CGFloat = JuktoConstants.cardRadius, padding: CGFloat = 14,
         @ViewBuilder content: () -> Content) {
        self.radius = radius; self.padding = padding; self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            }
    }
}

// MARK: - Progress
struct GlassProgressBar: View {
    var value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                Capsule(style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(value, 0), 1))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

// MARK: - Buttons
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(Capsule(style: .continuous).fill(prominent ? tint : Color.primary.opacity(0.07)))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(prominent ? 0 : 0.06)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.85 : 1))
            .animation(JuktoAnimation.pill, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.05)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(JuktoAnimation.pill, value: configuration.isPressed)
    }
}

struct ChoicePillStyle: ButtonStyle {
    var isSelected: Bool
    var isDimmed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(Capsule(style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05)))
            .opacity(isDimmed ? 0.4 : (configuration.isPressed ? 0.8 : 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(JuktoAnimation.pill, value: isSelected)
            .animation(JuktoAnimation.pill, value: configuration.isPressed)
    }
}

struct ChoicePill: View {
    let title: String
    var symbol: String? = nil
    var isSelected: Bool
    var isDimmed = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).symbolEffect(.bounce, value: isSelected)
                }
                Text(title)
            }
        }
        .buttonStyle(ChoicePillStyle(isSelected: isSelected, isDimmed: isDimmed))
    }
}

// MARK: - Segmented glass tabs
struct GlassTabs: View {
    let titles: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { i in
                Button { withAnimation(JuktoAnimation.tab) { selection = i } } label: {
                    Text(titles[i])
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .foregroundStyle(selection == i ? Color.primary : Color.secondary)
                        .background {
                            if selection == i {
                                Capsule(style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
