import SwiftUI

enum Platform: String, CaseIterable, Codable {
    case youtube, twitter, instagram, tiktok, reddit, unknown

    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .twitter: "X"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .reddit: "Reddit"
        case .unknown: "Web"
        }
    }

    var symbol: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .twitter: "bubble.left.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .reddit: "text.bubble.fill"
        case .unknown: "globe"
        }
    }

    var tint: Color {
        switch self {
        case .youtube: .juktoCoral
        case .twitter: .accentColor
        case .instagram: .juktoRosewood
        case .tiktok: .juktoLavender
        case .reddit: .juktoBronze
        case .unknown: .secondary
        }
    }

    static func detect(_ url: URL) -> Platform {
        let host = (url.host ?? "").lowercased()
        func match(_ d: String) -> Bool { host == d || host.hasSuffix("." + d) }
        if match("youtube.com") || match("youtu.be") || match("youtube-nocookie.com") { return .youtube }
        if match("twitter.com") || match("x.com") || match("fxtwitter.com") || match("vxtwitter.com") { return .twitter }
        if match("instagram.com") { return .instagram }
        if match("tiktok.com") { return .tiktok }
        if match("reddit.com") || match("redd.it") { return .reddit }
        return .unknown
    }
}
