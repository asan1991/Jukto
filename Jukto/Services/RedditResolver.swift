import Foundation

/// yt-dlp's Reddit extractor is unreliable, so resolve the post via api.reddit.com
/// and hand yt-dlp the HLS manifest (which carries audio, unlike fallback_url).
enum RedditResolver {
    static func resolve(_ url: URL) async throws -> VideoMetadata? {
        var postURL = url
        let host = (url.host ?? "").lowercased()
        // Share links (/s/…) and redd.it short links need a redirect hop first.
        if url.path.contains("/s/") || (host.hasSuffix("redd.it") && host != "v.redd.it") {
            var r = URLRequest(url: url); r.setValue(JuktoConstants.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, resp) = try await URLSession.shared.data(for: r)
            postURL = resp.url ?? url
        }
        guard let id = firstMatch(#"/comments/([a-z0-9]+)"#, in: postURL.path),
              let api = URL(string: "https://api.reddit.com/comments/\(id)?limit=1&raw_json=1") else { return nil }

        var req = URLRequest(url: api)
        req.setValue(JuktoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let children = (root.first?["data"] as? [String: Any])?["children"] as? [[String: Any]],
              var post = children.first?["data"] as? [String: Any] else { return nil }

        if media(of: post) == nil,
           let parent = (post["crosspost_parent_list"] as? [[String: Any]])?.first { post = parent }
        guard let rv = media(of: post),
              let stream = (rv["hls_url"] as? String) ?? (rv["fallback_url"] as? String),
              let streamURL = URL(string: stream) else { return nil }

        let preview = (((post["preview"] as? [String: Any])?["images"] as? [[String: Any]])?.first?["source"] as? [String: Any])?["url"] as? String
        let thumb = (preview ?? post["thumbnail"] as? String).flatMap(URL.init(string:))

        return VideoMetadata(
            title: (post["title"] as? String) ?? "Reddit video",
            uploader: (post["author"] as? String).map { "u/\($0)" },
            duration: (rv["duration"] as? NSNumber)?.doubleValue,
            thumbnail: thumb,
            platform: .reddit,
            originalURL: url,
            downloadURL: streamURL,
            maxHeight: (rv["height"] as? NSNumber)?.intValue
        )
    }

    private static func media(of post: [String: Any]) -> [String: Any]? {
        let m = (post["secure_media"] as? [String: Any]) ?? (post["media"] as? [String: Any])
        return m?["reddit_video"] as? [String: Any]
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
