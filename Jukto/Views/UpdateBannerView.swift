import SwiftUI

struct UpdateBannerView: View {
    @EnvironmentObject var updates: UpdateService

    private var visible: Bool {
        updates.updateAvailable || updates.isUpdating || updates.errorMessage != nil || updates.statusMessage != nil
    }

    var body: some View {
        if visible {
            GlassCard(radius: JuktoConstants.smallRadius, padding: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.callout)
                        if let d = detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if updates.isUpdating {
                        ProgressView().controlSize(.small)
                    } else if updates.updateAvailable {
                        Button("Update") { Task { await updates.updateAll() } }
                            .buttonStyle(PillButtonStyle(prominent: true, tint: .juktoLavender))
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var icon: String {
        if updates.errorMessage != nil { return "exclamationmark.triangle.fill" }
        if updates.updateAvailable || updates.isUpdating { return "arrow.down.circle.fill" }
        return "checkmark.circle.fill"
    }
    private var tint: Color {
        if updates.errorMessage != nil { return .juktoCoral }
        if updates.updateAvailable || updates.isUpdating { return .juktoLavender }
        return .juktoSuccess
    }
    private var title: String {
        if let e = updates.errorMessage { return e }
        if updates.isUpdating { return updates.statusMessage ?? "Updating…" }
        if updates.updateAvailable { return "Updates available" }
        return updates.statusMessage ?? ""
    }
    private var detail: String? {
        guard updates.updateAvailable, !updates.isUpdating else { return nil }
        var parts: [String] = []
        if updates.appUpdateAvailable, let l = updates.latestAppVersion {
            parts.append("Jukto \(JuktoConstants.appVersion) → \(l)")
        }
        if updates.ytdlpUpdateAvailable, let c = updates.currentVersion, let l = updates.latestVersion {
            parts.append("yt-dlp \(c) → \(l)")
        }
        if updates.ffmpegUpdateAvailable, let l = updates.latestFFmpeg {
            parts.append("ffmpeg → \(l)")
        }
        return parts.joined(separator: "  ·  ")
    }
}
