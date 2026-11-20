import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var downloads: DownloadViewModel

    var body: some View {
        if downloads.history.entries.isEmpty {
            emptyState("Finished downloads show up here", symbol: "clock")
        } else {
            VStack(spacing: 8) {
                ForEach(downloads.history.entries) { e in
                    let exists = FileManager.default.fileExists(atPath: e.path)
                    GlassCard(radius: JuktoConstants.smallRadius, padding: 10) {
                        HStack(spacing: 12) {
                            ThumbnailView(url: e.thumbnail.flatMap(URL.init(string:)), width: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    PlatformBadge(platform: e.platform)
                                    Text(e.format.uppercased()).font(.caption).foregroundStyle(.secondary)
                                    Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                                if !exists { Text("File moved or deleted").font(.caption).foregroundStyle(Color.juktoBronze) }
                            }
                            HStack(spacing: 6) {
                                if let src = e.sourceURL.flatMap(URL.init(string:)) {
                                    Button { downloads.openSource(src) } label: { Image(systemName: "link") }
                                        .buttonStyle(IconButtonStyle(tint: .accentColor)).help("Open the link in your browser and copy it")
                                }
                                if exists {
                                    Button { downloads.reveal(URL(fileURLWithPath: e.path)) } label: { Image(systemName: "magnifyingglass") }
                                        .buttonStyle(IconButtonStyle(tint: .accentColor)).help("Show in Finder")
                                }
                                Button { downloads.history.remove(e) } label: { Image(systemName: "trash") }
                                    .buttonStyle(IconButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
}
