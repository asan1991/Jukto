import SwiftUI

struct DownloadListView: View {
    @EnvironmentObject var downloads: DownloadViewModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                GlassTabs(titles: ["Downloads", "History"], selection: $tab)
                Spacer()
                if tab == 0, downloads.items.contains(where: { $0.status.isFinished }) {
                    Button("Clear finished") { downloads.clearFinished() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                if tab == 1, !downloads.history.entries.isEmpty {
                    Button("Clear history") { downloads.history.clear() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack {
                if tab == 0 { downloadsList.transition(.opacity) }
                else { HistoryView().transition(.opacity) }
            }
            .animation(JuktoAnimation.tab, value: tab)
        }
    }

    @ViewBuilder private var downloadsList: some View {
        if downloads.items.isEmpty {
            emptyState("No downloads yet", symbol: "arrow.down.circle")
        } else {
            VStack(spacing: 8) {
                ForEach(downloads.items) { item in DownloadRowView(item: item) }
            }
        }
    }
}

func emptyState(_ text: String, symbol: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 28)
}

struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var downloads: DownloadViewModel

    var body: some View {
        GlassCard(radius: JuktoConstants.smallRadius, padding: 10) {
            HStack(spacing: 12) {
                ThumbnailView(url: item.metadata.thumbnail, width: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.metadata.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundStyle(statusColor).lineLimit(2)
                    if item.status == .downloading, item.progress < 0.005 {
                        ProgressView().progressViewStyle(.linear).controlSize(.small)     // no figures yet
                    } else if item.status.isActive || item.status == .queued {
                        GlassProgressBar(value: item.progress, tint: item.status == .compressing ? .juktoLavender : .accentColor)
                    }
                }
                HStack(spacing: 6) { actions }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var statusText: String {
        switch item.status {
        case .queued: return "Waiting…"
        case .downloading:
            if item.progress >= 0.99 { return "Processing…" }
            // percent (or, when the total is unknown, the size so far) · speed · time left — always something to show
            var parts: [String] = []
            if item.progress >= 0.005 { parts.append(String(format: "%.0f%%", item.progress * 100)) }
            else if !item.sizeText.isEmpty { parts.append(item.sizeText) }
            if !item.speed.isEmpty { parts.append(item.speed) }
            if !item.eta.isEmpty { parts.append("\(item.eta) left") }
            if parts.isEmpty { return item.options.clipRange != nil ? "Cutting clip…" : "Starting…" }
            return parts.joined(separator: " · ")
        case .compressing: return String(format: "%@ · %.0f%%", item.phaseNote ?? "Working", item.progress * 100)
        case .completed: return "Saved to \(item.directory.lastPathComponent)"
        case .failed(let m): return m
        case .cancelled: return "Cancelled"
        }
    }
    private var statusColor: Color {
        switch item.status {
        case .completed: .juktoSuccess
        case .failed: .juktoCoral
        default: .secondary
        }
    }

    @ViewBuilder private var actions: some View {
        switch item.status {
        case .queued, .downloading, .compressing:
            Button { downloads.cancel(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle()).help("Cancel")
        case .completed:
            Button { downloads.openSource(item.metadata.originalURL) } label: { Image(systemName: "link") }
                .buttonStyle(IconButtonStyle(tint: .accentColor)).help("Open the link in your browser and copy it")
            if let url = item.outputURL {
                Button { downloads.reveal(url) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(IconButtonStyle(tint: .accentColor)).help("Show in Finder")
            }
            Button { downloads.remove(item) } label: { Image(systemName: "trash") }.buttonStyle(IconButtonStyle())
        case .failed, .cancelled:
            Button { downloads.retry(item) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(IconButtonStyle(tint: .accentColor)).help("Retry")
            Button { downloads.remove(item) } label: { Image(systemName: "trash") }.buttonStyle(IconButtonStyle())
        }
    }
}
