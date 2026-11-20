import Foundation

enum URLDetector {
    static func firstURL(in text: String) -> URL? {
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let det = try? NSDataDetector(types: types) else { return nil }
        let matches = det.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}

extension URLDetector {
    /// False for a site / channel / profile / feed page that has no particular video in it
    /// (e.g. youtube.com, youtube.com/@name, instagram.com/name). Unknown sites: false only for the bare home page.
    static func pointsToVideo(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map { String($0).lowercased() }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func hasQuery(_ name: String) -> Bool { query.contains { $0.name == name && !($0.value ?? "").isEmpty } }

        switch Platform.detect(url) {
        case .youtube:
            if host == "youtu.be" || host.hasSuffix(".youtu.be") { return !parts.isEmpty }
            guard let first = parts.first else { return false }
            if first == "watch" { return hasQuery("v") }
            return ["shorts", "live", "embed", "v", "clip"].contains(first) && parts.count >= 2
        case .instagram:
            guard let first = parts.first else { return false }
            if ["p", "reel", "reels", "tv", "stories"].contains(first) { return parts.count >= 2 }
            if first == "share" { return parts.count >= 3 }
            return parts.count >= 3 && ["p", "reel", "tv"].contains(parts[1])      // /username/reel/ID
        case .twitter:
            if let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }) { return i + 1 < parts.count }
            return parts.count >= 3 && parts[0] == "i" && parts[1] == "videos"
        case .tiktok:
            if host.hasPrefix("vm.") || host.hasPrefix("vt.") { return !parts.isEmpty }
            if let i = parts.firstIndex(where: { $0 == "video" || $0 == "photo" }) { return i + 1 < parts.count }
            guard let first = parts.first else { return false }
            return ["t", "v", "embed"].contains(first) && parts.count >= 2
        case .reddit:
            if host == "redd.it" || host.hasSuffix(".redd.it") { return !parts.isEmpty }
            if let i = parts.firstIndex(of: "comments") { return i + 1 < parts.count }
            if let i = parts.firstIndex(of: "s") { return i + 1 < parts.count }
            return false
        case .unknown:
            return !(parts.isEmpty && (url.query ?? "").isEmpty)
        }
    }
}
