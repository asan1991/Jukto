import Foundation
import SwiftUI

enum JuktoConstants {
    static let appName = "Jukto"
    static let author = "@asan_djantaliev"
    static let telegramURL = URL(string: "https://t.me/+z179h3EA99M3NDli")!
    static let usdtAddress = "0x0d9ecd06aad863aef47fc29017b74be2b3791a8f"
    static let mbankLabel = "Асан. Д."
    static let mainWindowID = "main"
    static let mainWindowIdentifier = "JuktoMainWindow"
    static let keychainService = "app.jukto.Jukto"

    static let maxConcurrentDownloads = 2
    static let cardRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let darkWindowAlpha: CGFloat = 0.95
    static let clipboardPollInterval: TimeInterval = 1.0
    static let minClipLength: Double = 1
    static let ytdlpRepo = "yt-dlp/yt-dlp"
    /// GitHub repository that hosts Jukto's own releases, as "username/Jukto". Replace YOUR-GITHUB-USERNAME once.
    static let appRepo = "YOUR-GITHUB-USERNAME/Jukto"
    static let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    static var userAgent: String { "Jukto/\(appVersion) (macOS)" }
    /// Used only in the sign-in window so sites such as Google accept it as a normal Safari.
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    enum Keys {
        static let saveDirectory = "saveDirectory"
        static let clipboardMonitoring = "clipboardMonitoring"
        static let autoAnalyze = "autoAnalyze"
        static let defaultFormat = "defaultFormat"
        static let defaultResolution = "defaultResolution"
        static let appearance = "appearance"          // "system" | "light" | "dark"
        static let showThanksOnClose = "showThanksOnClose"
        static let textScale = "textScale"            // 0.8 … 2.0, ⌘+ / ⌘− / ⌘0
        static let resumeOnLaunch = "resumeOnLaunch"
    }

    /// Never use Bundle.main.path(forResource:ofType:) — it can't see the bin/ folder reference.
    static var resourcesPath: String { Bundle.main.bundlePath + "/Contents/Resources" }
    static var binPath: String { resourcesPath + "/bin" }

    /// Private (0700) per-user folder for history and updated components.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Jukto", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }
}

extension Double {
    var timecode: String {
        let t = Int(self.rounded()); let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Double {
    /// Like `timecode`, but keeps one decimal when the value isn't a whole second (e.g. 1:23.5).
    var preciseTimecode: String {
        let whole = Int(self); let frac = self - Double(whole)
        let base = Double(whole).timecode
        return frac >= 0.05 ? base + ".\(Int((frac * 10).rounded(.down)))" : base
    }
}

extension String {
    var sanitizedFilename: String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(120))
    }
}
