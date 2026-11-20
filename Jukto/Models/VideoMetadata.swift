import Foundation

struct SubtitleTrack: Identifiable, Equatable, Hashable {
    let code: String
    let name: String
    let isAuto: Bool
    var id: String { (isAuto ? "auto:" : "sub:") + code }
}

/// The raw `yt-dlp -J` answer, kept so the download can reuse it instead of extracting the page a second time.
/// Compared by identity so SwiftUI never has to compare megabytes of JSON.
final class InfoBox: Equatable, @unchecked Sendable {
    let data: Data
    init(_ data: Data) { self.data = data }
    static func == (a: InfoBox, b: InfoBox) -> Bool { a === b }
}

struct VideoMetadata: Equatable {
    var title: String
    var uploader: String?
    var duration: Double?
    var thumbnail: URL?
    var platform: Platform
    var originalURL: URL
    /// What is actually handed to yt-dlp (differs from originalURL for Reddit).
    var downloadURL: URL
    var maxHeight: Int?
    var subtitleTracks: [SubtitleTrack] = []
    /// Language codes of the separate audio tracks the site offers (e.g. dubbed YouTube audio).
    var audioLanguages: [String] = []
    /// Set for streams found by the capture browser (page URL used as Referer, cookies from that session).
    var referer: URL? = nil
    var cookies: [StoredCookie] = []
    var sniffed = false
    /// True when the site only answered once yt-dlp imitated a real browser.
    var impersonate = false
    /// Browser whose sign-in (cookies) was needed to read the page, e.g. "chrome".
    var browser: String? = nil
    /// Analysis JSON of a single video (nil for playlists / carousels / captured streams → normal extraction).
    var info: InfoBox? = nil
}

extension VideoMetadata {
    struct Raw: Decodable {
        var id: String?
        var title: String?
        var uploader: String?
        var channel: String?
        var duration: Double?
        var thumbnail: String?
        var formats: [RawFormat]?
        var entries: [Raw?]?
    }
    struct RawFormat: Decodable {
        var height: Int?
    }

    static func parse(_ data: Data, originalURL: URL, platform: Platform) throws -> VideoMetadata {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        // Carousels / playlists: use the first entry.
        let src = raw.entries?.compactMap { $0 }.first ?? raw
        let heights = (src.formats ?? []).compactMap { $0.height }
        var md = VideoMetadata(
            title: src.title ?? raw.title ?? "Untitled",
            uploader: src.uploader ?? src.channel ?? raw.uploader,
            duration: src.duration ?? raw.duration,
            thumbnail: (src.thumbnail ?? raw.thumbnail).flatMap(URL.init(string:)),
            platform: platform,
            originalURL: originalURL,
            downloadURL: originalURL,
            maxHeight: heights.max()
        )
        let extra = extras(from: data)
        if raw.entries == nil, !(raw.formats ?? []).isEmpty { md.info = InfoBox(data) }
        md.subtitleTracks = extra.subs
        md.audioLanguages = extra.langs
        return md
    }

    /// Best-effort (never throws): subtitle tracks and audio languages, read leniently so odd JSON can't break analysis.
    private static func extras(from data: Data) -> (subs: [SubtitleTrack], langs: [String]) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], []) }
        let root = (obj["entries"] as? [Any])?.compactMap { $0 as? [String: Any] }.first ?? obj
        let videoLang = (root["language"] as? String)?.lowercased()

        func displayName(_ code: String, _ v: Any?) -> String {
            if let n = (v as? [[String: Any]])?.compactMap({ $0["name"] as? String }).first, !n.isEmpty { return n }
            return Locale.current.localizedString(forIdentifier: code) ?? code
        }

        var tracks: [SubtitleTrack] = []
        if let subs = root["subtitles"] as? [String: Any] {
            for (code, v) in subs where code != "live_chat" {
                tracks.append(SubtitleTrack(code: code, name: displayName(code, v), isAuto: false))
            }
        }
        tracks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Auto captions come in hundreds of translations; keep only the video's own spoken language.
        if let auto = root["automatic_captions"] as? [String: Any] {
            var autoTracks: [SubtitleTrack] = []
            for (code, v) in auto {
                let isOriginal = code.hasSuffix("-orig") || (videoLang != nil && code.lowercased() == videoLang)
                if isOriginal { autoTracks.append(SubtitleTrack(code: code, name: displayName(code, v) + " (auto)", isAuto: true)) }
            }
            autoTracks.sort { $0.name < $1.name }
            tracks += autoTracks
        }

        var langs = Set<String>()
        for f in (root["formats"] as? [[String: Any]]) ?? [] {
            if (f["vcodec"] as? String) == "none", let l = f["language"] as? String, !l.isEmpty { langs.insert(l) }
        }
        return (Array(tracks.prefix(60)), langs.sorted())
    }
}
