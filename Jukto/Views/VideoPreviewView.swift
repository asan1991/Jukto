import SwiftUI

struct PlatformBadge: View {
    let platform: Platform
    var body: some View {
        Label(platform.displayName, systemImage: platform.symbol)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(platform.tint)
            .background(Capsule(style: .continuous).fill(platform.tint.opacity(0.14)))
    }
}

struct ThumbnailView: View {
    let url: URL?
    var width: CGFloat = 160
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Rectangle().fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: JuktoConstants.smallRadius, style: .continuous))
    }
}

struct VideoPreviewView: View {
    let metadata: VideoMetadata
    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                ThumbnailView(url: metadata.thumbnail)
                    .overlay(alignment: .bottomTrailing) {
                        if let d = metadata.duration {
                            Text(d.timecode)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(.black.opacity(0.7)))
                                .foregroundStyle(.white).padding(6)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    PlatformBadge(platform: metadata.platform)
                    Text(metadata.title).font(.headline).lineLimit(3)
                    if let u = metadata.uploader { Text(u).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    if let h = metadata.maxHeight { Text("Up to \(h)p").font(.caption).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
