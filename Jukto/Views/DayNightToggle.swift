import SwiftUI

/// Minimal day / night switch: a slim capsule with a sliding sun / moon knob.
/// The first click leaves "follow macOS" and fixes the theme to light or dark.
struct DayNightToggle: View {
    @AppStorage(JuktoConstants.Keys.appearance) private var mode = "system"
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { mode == "dark" || (mode == "system" && scheme == .dark) }

    var body: some View {
        Button { mode = isDark ? "light" : "dark" } label: {
            ZStack(alignment: isDark ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                Circle()
                    .fill(isDark ? Color(white: 0.30) : Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                    .overlay(
                        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isDark ? Color.juktoLavender : Color.orange)
                    )
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: 46, height: 26)
            .animation(.easeInOut(duration: 0.18), value: isDark)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isDark ? "Switch to light theme" : "Switch to dark theme")
        .accessibilityLabel("Day and night theme")
    }
}
