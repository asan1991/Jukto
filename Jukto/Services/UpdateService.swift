import Foundation
import AppKit

// MARK: - Network + verification helpers
enum ComponentUpdater {
    private static let ffRepo = "https://github.com/shaka-project/static-ffmpeg-binaries"
    private static var ffArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }
    private static let ffTagKey = "installedFFmpegTag"

    /// Which ffmpeg build is in use: the one installed by an in-app update, else the one shipped in the app.
    static var installedFFmpegTag: String? {
        if let t = UserDefaults.standard.string(forKey: ffTagKey) { return t }
        let path = JuktoConstants.resourcesPath + "/ffmpeg-tag.txt"
        return (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func forgetInstalledFFmpegTag() { UserDefaults.standard.removeObject(forKey: ffTagKey) }

    /// Reads the tag from GitHub's /releases/latest redirect, which has no API rate limit.
    private static func latestTag(of repoURL: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(repoURL)/releases/latest")!)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 20
        req.setValue(JuktoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let url = resp.url, url.pathComponents.contains("tag"),
              let tag = url.pathComponents.last, tag != "tag", !tag.isEmpty else {
            throw JuktoError.message("Couldn't read the latest release version.")
        }
        return tag
    }

    // MARK: Jukto itself (GitHub Releases of JuktoConstants.appRepo)
    static var appConfigured: Bool { !JuktoConstants.appRepo.contains("YOUR-GITHUB-USERNAME") }
    private static var appRepoURL: String { "https://github.com/\(JuktoConstants.appRepo)" }
    private static var appDMGKind: String {
        #if arch(arm64)
        return "AppleSilicon"
        #else
        return "Intel"
        #endif
    }

    /// "v1.0.2" -> "1.0.2"
    static func appVersion(fromTag tag: String) -> String { tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag }

    /// Tag of the newest published (non-draft, non-prerelease) release of Jukto.
    static func latestApp() async throws -> String {
        guard appConfigured else {
            throw JuktoError.message("Set your GitHub repository in JuktoConstants.swift (appRepo) first.")
        }
        return try await latestTag(of: appRepoURL)
    }

    /// Downloads the .dmg for this Mac's CPU, checks it against the release's published .sha256 and saves it in Downloads.
    static func downloadApp(tag: String) async throws -> URL {
        guard !tag.isEmpty, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else {
            throw JuktoError.message("Unexpected release name.")
        }
        let version = appVersion(fromTag: tag)
        let base = "\(appRepoURL)/releases/download/\(tag)/"
        let name = "Jukto-\(version)-\(appDMGKind).dmg"
        guard let sumsURL = URL(string: base + "Jukto-\(version).sha256"), let dmgURL = URL(string: base + name) else {
            throw JuktoError.message("Unexpected release name.")
        }
        let sums = try await fetchText(sumsURL)
        guard let line = sums.split(separator: "\n").first(where: { $0.contains(name) }),
              let expected = firstHex64(String(line)) else {
            throw JuktoError.message("The release has no checksum for \(name) — download skipped.")
        }
        let file = try await download(dmgURL)
        try verify(file, expected: expected)

        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: file, to: dest)
        return dest
    }

    static func latestYTDLP() async throws -> String { try await latestTag(of: "https://github.com/\(JuktoConstants.ytdlpRepo)") }
    static func latestFFmpeg() async throws -> String { try await latestTag(of: ffRepo) }

    private static func fetchText(_ url: URL) async throws -> String {
        guard url.scheme == "https" else { throw JuktoError.message("Refusing non-HTTPS download.") }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JuktoError.message("Couldn't fetch release information.") }
        return String(decoding: data, as: UTF8.self)
    }

    private static func download(_ url: URL) async throws -> URL {
        guard url.scheme == "https" else { throw JuktoError.message("Refusing non-HTTPS download.") }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw JuktoError.message("Download failed.") }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("jukto-dl-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private static func verify(_ file: URL, expected: String) throws {
        guard try Hashing.sha256(of: file) == expected.lowercased() else {
            try? FileManager.default.removeItem(at: file)
            throw JuktoError.message("Checksum mismatch — update aborted for your safety.")
        }
    }

    private static func firstHex64(_ text: String) -> String? {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init).first { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }?.lowercased()
    }

    /// GitHub lists a SHA-256 next to every release asset on the release page.
    private static func githubDigest(in html: String, asset: String) -> String? {
        let pattern = "/" + NSRegularExpression.escapedPattern(for: asset) + "\"[\\s\\S]{0,1500}?sha256:([0-9a-f]{64})"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    static func updateYTDLP() async throws {
        let tag = try await latestYTDLP()
        let base = "https://github.com/\(JuktoConstants.ytdlpRepo)/releases/download/\(tag)/"
        let sums = try await fetchText(URL(string: base + "SHA2-256SUMS")!)
        guard let line = sums.split(separator: "\n").first(where: { $0.hasSuffix("yt-dlp_macos") }),
              let expected = firstHex64(String(line)) else {
            throw JuktoError.message("No published checksum for yt-dlp — update skipped.")
        }
        let file = try await download(URL(string: base + "yt-dlp_macos")!)
        try verify(file, expected: expected)
        try await ComponentStore.install(file, name: "yt-dlp", signIfNeeded: true)

        let out = LockedLines()
        let code = try await runProcess(ComponentStore.binDir.appendingPathComponent("yt-dlp").path, ["--version"],
                                        onOut: { out.append($0) })
        guard code == 0, out.lines.first != nil else {
            ComponentStore.remove("yt-dlp")
            throw JuktoError.message("The new yt-dlp failed its self-test and was discarded.")
        }
    }

    static func updateFFmpeg() async throws {
        let tag = try await latestFFmpeg()
        let html = try await fetchText(URL(string: "\(ffRepo)/releases/expanded_assets/\(tag)")!)
        for name in ["ffmpeg", "ffprobe"] {
            let asset = "\(name)-osx-\(ffArch)"
            guard let expected = githubDigest(in: html, asset: asset) else {
                throw JuktoError.message("No published checksum for \(asset) — update skipped.")
            }
            let file = try await download(URL(string: "\(ffRepo)/releases/download/\(tag)/\(asset)")!)
            try verify(file, expected: expected)
            try await ComponentStore.install(file, name: name, signIfNeeded: true)   // signs, hashes, stores record

            // Self-test the installed (now signed) binary; discard it if it doesn't run.
            let test = try await runProcess(ComponentStore.binDir.appendingPathComponent(name).path, ["-version"])
            guard test == 0 else {
                ComponentStore.remove(name)
                throw JuktoError.message("The new \(name) failed its self-test and was discarded.")
            }
        }
        UserDefaults.standard.set(tag, forKey: ffTagKey)
    }
}

// MARK: - Observable service
@MainActor
final class UpdateService: ObservableObject {
    @Published var currentVersion: String?     // yt-dlp
    @Published var latestVersion: String?
    @Published var ffmpegVersion: String?
    @Published var latestFFmpeg: String?
    @Published var latestAppTag: String?       // newest Jukto release on GitHub
    private var downloadedAppTag: String?      // already downloaded this session
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    var ytdlpUpdateAvailable: Bool {
        guard let c = currentVersion, let l = latestVersion else { return false }
        return l.compare(c, options: .numeric) == .orderedDescending
    }
    var ffmpegUpdateAvailable: Bool {
        guard let installed = ComponentUpdater.installedFFmpegTag, let l = latestFFmpeg else { return false }
        return installed != l
    }
    var latestAppVersion: String? { latestAppTag.map(ComponentUpdater.appVersion(fromTag:)) }
    var appUpdateAvailable: Bool {
        guard let l = latestAppVersion, latestAppTag != downloadedAppTag else { return false }
        return l.compare(JuktoConstants.appVersion, options: .numeric) == .orderedDescending
    }
    var updateAvailable: Bool { appUpdateAvailable || ytdlpUpdateAvailable || ffmpegUpdateAvailable }

    func check(silent: Bool = true) async {
        guard !isChecking, !isUpdating else { return }
        isChecking = true; errorMessage = nil
        defer { isChecking = false }
        currentVersion = await YTDLPService.shared.version()
        ffmpegVersion = await FFmpegService.version()
        do { latestVersion = try await ComponentUpdater.latestYTDLP() }
        catch { if !silent { errorMessage = "Couldn't check yt-dlp: \(error.localizedDescription)" } }
        latestFFmpeg = try? await ComponentUpdater.latestFFmpeg()
        do { latestAppTag = try await ComponentUpdater.latestApp() }
        catch { latestAppTag = nil; if !silent, errorMessage == nil { errorMessage = "Couldn't check Jukto: \(error.localizedDescription)" } }
        if !updateAvailable && !silent && errorMessage == nil { flash("Everything is up to date") }
    }

    func updateAll() async {
        guard !isUpdating else { return }
        isUpdating = true; errorMessage = nil
        do {
            if ytdlpUpdateAvailable { statusMessage = "Updating yt-dlp…"; try await ComponentUpdater.updateYTDLP() }
            if ffmpegUpdateAvailable { statusMessage = "Updating ffmpeg…"; try await ComponentUpdater.updateFFmpeg() }
            var appDMG: URL?
            if appUpdateAvailable, let tag = latestAppTag {
                statusMessage = "Downloading Jukto \(ComponentUpdater.appVersion(fromTag: tag))…"
                appDMG = try await ComponentUpdater.downloadApp(tag: tag)
                downloadedAppTag = tag
            }
            statusMessage = nil
            isUpdating = false
            await check(silent: true)
            if let dmg = appDMG {
                NSWorkspace.shared.open(dmg)     // mounts the disk image: drag Jukto into Applications
                flash("Jukto downloaded to Downloads — drag it into Applications")
            } else {
                flash("Updated successfully")
            }
        } catch {
            isUpdating = false
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
