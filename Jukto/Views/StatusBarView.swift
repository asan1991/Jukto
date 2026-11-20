import SwiftUI
import AppKit

struct StatusBarView: View {
    @EnvironmentObject var downloads: DownloadViewModel
    @EnvironmentObject var updates: UpdateService
    @EnvironmentObject var monitor: ClipboardMonitor
    @State private var checksum: String?

    var body: some View {
        VStack(spacing: 0) {
            if let sum = checksum {
                HStack(spacing: 6) {
                    Text("SHA-256 · \(AppChecksum.variant)").fontWeight(.semibold)
                    Text(sum).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 6)
            }
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Circle().fill(downloads.activeCount > 0 ? Color.accentColor : Color.juktoSuccess).frame(width: 6, height: 6)
            Text(downloads.activeCount > 0 ? "\(downloads.activeCount) active" : "Ready")
            if monitor.isRunning {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.tertiary).help("Watching the clipboard for links")
            }
            Spacer()

            // yt-dlp version — click to check for updates
            Button {
                Task { await updates.check(silent: false) }
            } label: {
                HStack(spacing: 4) {
                    if updates.isChecking { ProgressView().controlSize(.mini) }
                    Text(updates.currentVersion.map { "yt-dlp \($0)" } ?? "yt-dlp")
                }
            }
            .buttonStyle(.plain)
            .disabled(updates.isChecking || updates.isUpdating)
            .help("Check for updates")

            Button {
                Task {
                    let sum = await Task.detached(priority: .utility) { try? AppChecksum.compute() }.value
                    guard let sum else { ToastCenter.shared.show("Couldn't compute the SHA-256.", seconds: 2); return }
                    checksum = sum
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sum, forType: .string)
                    ToastCenter.shared.show("SHA-256 copied to clipboard.", seconds: 2)
                }
            } label: {
                Text("· Jukto v\(JuktoConstants.appVersion)")
            }
            .buttonStyle(.plain)
            .help("Show this app's SHA-256 (the same value is in the release's in-app checksum file) and copy it")

            // Clickable attribution — opens the Telegram link
            Link(destination: JuktoConstants.telegramURL) {
                Text("· Made by \(JuktoConstants.author)")
                    .fontWeight(.semibold)
                    .underline(false)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}
