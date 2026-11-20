import Foundation
import Combine

// MARK: - Per-site sign-in configuration
extension Platform: Identifiable {
    var id: String { rawValue }
    var supportsLogin: Bool { self != .unknown }

    var loginURL: URL? {
        switch self {
        case .youtube: return URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F")
        case .instagram: return URL(string: "https://www.instagram.com/accounts/login/")
        case .twitter: return URL(string: "https://x.com/i/flow/login")
        case .tiktok: return URL(string: "https://www.tiktok.com/login")
        case .reddit: return URL(string: "https://www.reddit.com/login")
        case .unknown: return nil
        }
    }

    /// The sign-in window may only navigate to these hosts.
    var trustedHosts: [String] {
        switch self {
        case .youtube: return ["youtube.com", "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com"]
        case .instagram: return ["instagram.com", "cdninstagram.com", "facebook.com", "fbcdn.net"]
        case .twitter: return ["x.com", "twitter.com", "twimg.com"]
        case .tiktok: return ["tiktok.com", "tiktokcdn.com", "tiktokv.com", "ibytedtos.com", "byteoversea.com"]
        case .reddit: return ["reddit.com", "redditstatic.com", "redditmedia.com"]
        case .unknown: return []
        }
    }
    static let ssoHosts = ["google.com", "gstatic.com", "apple.com", "facebook.com", "fbcdn.net"]

    /// Only cookies from these domains are ever read from the sign-in window.
    var cookieDomains: [String] {
        switch self {
        case .youtube: return ["youtube.com", "google.com"]
        case .instagram: return ["instagram.com"]
        case .twitter: return ["x.com", "twitter.com"]
        case .tiktok: return ["tiktok.com"]
        case .reddit: return ["reddit.com"]
        case .unknown: return []
        }
    }
    /// Presence of any of these means "signed in".
    var sessionCookieNames: [String] {
        switch self {
        case .youtube: return ["LOGIN_INFO", "__Secure-3PSID", "SAPISID"]
        case .instagram: return ["sessionid"]
        case .twitter: return ["auth_token"]
        case .tiktok: return ["sessionid", "sid_tt"]
        case .reddit: return ["reddit_session", "token_v2"]
        case .unknown: return []
        }
    }

    static func hostMatches(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
    func isTrusted(host: String) -> Bool {
        (trustedHosts + Platform.ssoHosts).contains { Platform.hostMatches(host, $0) }
    }
}

enum AuthDetector {
    private static let markers = [
        "login required", "log in", "sign in", "logged in", "private video", "confirm your age",
        "age-restricted", "age restricted", "rate-limit reached", "not granting access",
        "empty media response", "restricted video", "requires authentication", "use --cookies",
        "members-only", "this content may be inappropriate"
    ]
    static func looksLikeAuthError(_ text: String) -> Bool {
        let l = text.lowercased()
        return markers.contains { l.contains($0) }
    }
}

// MARK: - Cookie storage (Keychain, encrypted at rest by macOS)
struct StoredCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Double?
    var secure: Bool
    var httpOnly: Bool
}

extension StoredCookie {
    init(_ c: HTTPCookie) {
        self.init(name: c.name, value: c.value, domain: c.domain, path: c.path,
                  expires: c.expiresDate?.timeIntervalSince1970, secure: c.isSecure, httpOnly: c.isHTTPOnly)
    }
}

enum CookieVault {
    private static func account(_ p: Platform) -> String { "cookies.\(p.rawValue)" }

    static func load(_ p: Platform) -> [StoredCookie] {
        guard let data = KeychainStore.get(account: account(p)),
              let list = try? JSONDecoder().decode([StoredCookie].self, from: data) else { return [] }
        let now = Date().timeIntervalSince1970
        return list.filter { ($0.expires ?? now + 1) > now }
    }
    static func hasLogin(_ p: Platform) -> Bool { !load(p).isEmpty }

    static func save(_ cookies: [StoredCookie], for p: Platform) {
        guard let data = try? JSONEncoder().encode(cookies) else { return }
        KeychainStore.set(data, account: account(p))
    }
    static func remove(_ p: Platform) { KeychainStore.delete(account: account(p)) }
}

/// A short-lived cookies.txt handed to yt-dlp. Lives in a private 0700 folder and is deleted right after the run.
final class TempCookieFile {
    let url: URL
    private let dir: URL

    convenience init?(platform: Platform) {
        guard platform.supportsLogin else { return nil }
        self.init(cookies: CookieVault.load(platform))
    }

    init?(cookies: [StoredCookie]) {
        guard !cookies.isEmpty else { return nil }
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("jukto-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return nil }

        func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\t", with: "") }
        let fallbackExpiry = Int(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970)
        var text = "# Netscape HTTP Cookie File\n"
        for c in cookies {
            let domain = (c.httpOnly ? "#HttpOnly_" : "") + clean(c.domain)
            let sub = c.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            text += "\(domain)\t\(sub)\t\(clean(c.path))\t\(c.secure ? "TRUE" : "FALSE")\t\(c.expires.map { Int($0) } ?? fallbackExpiry)\t\(clean(c.name))\t\(clean(c.value))\n"
        }
        let f = d.appendingPathComponent("cookies.txt")
        guard FileManager.default.createFile(atPath: f.path, contents: Data(text.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            try? FileManager.default.removeItem(at: d); return nil
        }
        self.dir = d; self.url = f
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

// MARK: - Coordinator
@MainActor
final class AuthCoordinator: ObservableObject {
    @Published var request: Platform?
    @Published var revision = 0          // bumps whenever a login is added or removed
    var onLoggedIn: ((Platform) -> Void)?

    func requestLogin(_ p: Platform) { guard p.supportsLogin else { return }; request = p }
    func completed(_ p: Platform) { request = nil; revision += 1; onLoggedIn?(p) }
    func cancel() { request = nil }
    func signOut(_ p: Platform) { CookieVault.remove(p); revision += 1 }
    func isSignedIn(_ p: Platform) -> Bool { _ = revision; return CookieVault.hasLogin(p) }
}
