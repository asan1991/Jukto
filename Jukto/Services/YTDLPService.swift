import Foundation

actor YTDLPService {
    static let shared = YTDLPService()

    /// --ignore-config / --no-plugin-dirs: never load config files or plugins from the user's home folder.
    private static let baseArgs = ["--ignore-config", "--no-plugin-dirs", "--no-warnings"]

    func version() async -> String? {
        let out = LockedLines()
        guard let code = try? await runProcess(JuktoEnvironment.ytdlpPath, ["--version"], onOut: { out.append($0) }),
              code == 0 else { return nil }
        return out.lines.first
    }

    // MARK: analyze
    func fetchMetadata(for url: URL) async throws -> VideoMetadata {
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ytdlpPath)
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw JuktoError.message("Only http(s) links are supported.")
        }
        let platform = Platform.detect(url)

        if platform == .reddit, let resolved = try? await RedditResolver.resolve(url) { return resolved }

        // 1. the normal way (with the sign-in saved in Jukto, if any)
        let first: JuktoError
        do {
            return try await infoAttempt(url: url, platform: platform, extra: [], browser: nil)
        } catch let e as JuktoError { first = e }
        if Task.isCancelled { throw CancellationError() }

        // 2. some sites only answer to a real browser: imitate Chrome's TLS/HTTP fingerprint
        if platform == .unknown,
           var md = try? await infoAttempt(url: url, platform: platform, extra: ["--impersonate", "chrome"], browser: nil) {
            md.impersonate = true
            return md
        }

        // 3. the sign-in of a browser the person already uses (Chrome, Brave, Edge, Firefox, Safari) — only when the
        //    site wants a login (or is unknown), and only after everything above failed.
        let wantsLogin = AuthDetector.looksLikeAuthError(first.localizedDescription)
        if wantsLogin || platform == .unknown {
            for b in Self.installedBrowsers() {
                if Task.isCancelled { throw CancellationError() }
                if var md = try? await infoAttempt(url: url, platform: platform, extra: [], browser: b) {
                    md.browser = b
                    return md
                }
            }
        }

        // 4. nothing worked. Stories are tried without an account first; only now is the sign-in offered.
        if case .authRequired = first { throw first }
        if platform == .instagram, url.path.contains("/stories/"), !CookieVault.hasLogin(.instagram) {
            throw JuktoError.authRequired(.instagram, first.localizedDescription)
        }
        throw first
    }

    /// Browsers on this Mac whose cookies yt-dlp can read, in the order they are tried.
    private static func installedBrowsers() -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let known: [(String, String)] = [
            ("chrome", "Google Chrome"), ("brave", "Brave Browser"), ("edge", "Microsoft Edge"),
            ("firefox", "Firefox"), ("vivaldi", "Vivaldi"), ("opera", "Opera"), ("safari", "Safari")]
        return known.filter { fm.fileExists(atPath: "/Applications/\($0.1).app") || fm.fileExists(atPath: home + "/Applications/\($0.1).app") }
            .map(\.0)
    }

    /// Extra arguments that make YouTube hand over EVERY format, 8K included: the default clients plus android_vr
    /// (which lists 4K/8K without needing a token), and no translated auto-captions (hundreds of them: slow to list).
    private static func youtubeArgs(clients: String = "default,android_vr") -> [String] {
        ["--extractor-args", "youtube:player_client=\(clients);skip=translated_subs"]
    }

    private func infoAttempt(url: URL, platform: Platform, extra: [String], browser: String?) async throws -> VideoMetadata {
        let cookies = browser == nil ? TempCookieFile(platform: platform) : nil
        defer { cookies?.cleanup() }

        var args = Self.baseArgs + ["-J", "--no-playlist", "--skip-download", "--socket-timeout", "20"] + extra
        if platform == .youtube { args += Self.youtubeArgs() }
        if let b = browser { args += ["--cookies-from-browser", b] }
        if let c = cookies { args += ["--cookies", c.url.path] }
        args += ["--", url.absoluteString]

        let out = LockedLines(), err = LockedLines()
        let code = try await runProcess(JuktoEnvironment.ytdlpPath, args,
                                        onOut: { out.append($0) }, onErr: { err.append($0) })
        guard code == 0 else { throw Self.classify(err, platform: platform, hadCookies: cookies != nil, code: code) }
        guard let json = out.lines.last(where: { $0.hasPrefix("{") })?.data(using: .utf8) else {
            throw JuktoError.message("Couldn't read video information.")
        }
        return try VideoMetadata.parse(json, originalURL: url, platform: platform)
    }

    // MARK: download
    func download(metadata: VideoMetadata,
                  options: DownloadOptions,
                  directory: URL,
                  stamp: String,
                  handle: ProcessHandle,
                  onProgress: @escaping @Sendable (ProgressUpdate) -> Void) async throws -> URL {
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ytdlpPath)
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ffmpegPath)

        let useBrowser = metadata.browser
        let cookies: TempCookieFile? = useBrowser != nil ? nil
            : (metadata.cookies.isEmpty ? TempCookieFile(platform: metadata.platform) : TempCookieFile(cookies: metadata.cookies))
        defer { cookies?.cleanup() }

        var args: [String] = Self.baseArgs + [
            "--no-playlist", "--newline", "--progress", "--no-mtime",
            // speed: 16 parallel fragment connections, big read buffer, auto re-extract when a site throttles
            "-N", "16", "--buffer-size", "1M", "--throttled-rate", "100K",
            "--retries", "10", "--fragment-retries", "10", "--socket-timeout", "20",
            "--progress-template",
            "download:CLIPPROG %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s",
            "--print", "after_move:CLIPPATH %(filepath)s",
            "--ffmpeg-location", JuktoEnvironment.ffmpegDirectory,
            "-P", directory.path
        ]
        // The file name is fixed per download, so a retry or a restart continues the same partial file (yt-dlp resumes it).
        args += ["-o", outputTemplate(for: metadata, stamp: stamp)]
        args += formatArgs(options, platform: metadata.platform)
        if metadata.platform == .youtube { args += ["--http-chunk-size", "10M"] }
        if let r = options.clipRange {
            // Stream-copy cut: no re-encoding, so it is fast and light. It starts at the nearest keyframe.
            args += ["--download-sections", String(format: "*%.2f-%.2f", r.lowerBound, r.upperBound),
                     "--downloader-args", "ffmpeg_i:-multiple_requests 1 -probesize 5M -analyzeduration 3M -reconnect 1 -reconnect_streamed 1"]
        }
        if let c = cookies { args += ["--cookies", c.url.path] }
        if let b = useBrowser { args += ["--cookies-from-browser", b] }
        if metadata.sniffed {                       // look like the browser that found the stream
            args += ["--user-agent", JuktoConstants.browserUserAgent]
            if let ref = metadata.referer { args += ["--referer", ref.absoluteString] }
        }
        if metadata.impersonate { args += ["--impersonate", "chrome"] }
        let finalArgs = args
        let clipLen = options.clipRange.map { $0.upperBound - $0.lowerBound }
        let totalLen = clipLen ?? metadata.duration

        func attempt(_ tail: [String]) async throws -> (code: Int32, path: String?, errors: LockedLines) {
            let holder = OutputPathHolder()
            let errors = LockedLines()
            let throttle = ProgressThrottle()
            let meter = SpeedMeter()
            let code = try await runProcess(JuktoEnvironment.ytdlpPath, finalArgs + tail, handle: handle, onOut: { raw in
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("CLIPPATH ") {
                    holder.path = String(line.dropFirst("CLIPPATH ".count))
                } else if line.hasPrefix("CLIPPROG "), let u = Self.parseProgress(line, meter: meter),
                          throttle.shouldEmit(force: (u.fraction ?? 0) >= 0.99) {
                    onProgress(u)
                }
            }, onErr: { line in
                // A trimmed clip (or a stream ffmpeg downloads) is reported by ffmpeg as `time=… size=…`: show it as progress.
                if let t = Self.ffmpegSeconds(line) {
                    if throttle.shouldEmit() {
                        let bytes = Self.ffmpegBytes(line)
                        let sp = bytes.flatMap { meter.update(bytes: $0) }
                        let frac = totalLen.flatMap { $0 > 0 ? min(0.95, t / $0) : nil }
                        onProgress(ProgressUpdate(fraction: frac,
                                                  speed: sp.map(Self.speedText) ?? "",
                                                  eta: "",
                                                  size: bytes.map(Self.sizeText) ?? ""))
                    }
                } else {
                    errors.append(line)
                }
            })
            return (code, holder.path, errors)
        }

        // Reuse the analysis result: yt-dlp skips a whole second extraction, which was the long pause before
        // every download. If that saved info has gone stale, it falls back to extracting afresh.
        let plain = ["--", metadata.downloadURL.absoluteString]
        var plans: [[String]] = []
        var infoFile: URL?
        if let box = metadata.info {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("jukto-info-\(UUID().uuidString).json")
            if (try? box.data.write(to: u, options: .atomic)) != nil { infoFile = u; plans.append(["--load-info-json", u.path]) }
        }
        defer { if let f = infoFile { try? FileManager.default.removeItem(at: f) } }
        if metadata.platform == .youtube {
            // "Download 8K by any means": fresh extraction with the extra clients, then another client set,
            // then any best video+audio into MKV (holds every codec).
            plans.append(Self.youtubeArgs() + plain)
            plans.append(Self.youtubeArgs(clients: "android_vr,tv") + plain)
            plans.append(Self.youtubeArgs() + ["-f", "bv*+ba/b", "--merge-output-format", "mkv"] + plain)
        } else {
            plans.append(plain)
        }

        var result: (code: Int32, path: String?, errors: LockedLines) = (1, nil, LockedLines())
        for tail in plans {
            result = try await attempt(tail)
            if handle.isCancelled { break }
            if result.code == 0, let p = result.path, FileManager.default.fileExists(atPath: p) { break }
            // A sign-in problem is not fixed by another try with the same account.
            if AuthDetector.looksLikeAuthError(result.errors.lines.joined(separator: " ")) { break }
        }

        if handle.isCancelled { throw CancellationError() }
        guard result.code == 0, let path = result.path, FileManager.default.fileExists(atPath: path) else {
            throw Self.classify(result.errors, platform: metadata.platform, hadCookies: cookies != nil, code: result.code)
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: helpers
    private static func classify(_ err: LockedLines, platform: Platform, hadCookies: Bool, code: Int32) -> JuktoError {
        let msg = err.lastError ?? "yt-dlp exited with code \(code)"
        if platform.supportsLogin, AuthDetector.looksLikeAuthError(err.lines.joined(separator: " ")) {
            if !hadCookies { return .authRequired(platform, msg) }
            return .message(msg + "\n\nYour saved \(platform.displayName) sign-in may have expired. Sign in again from Settings → Accounts.")
        }
        return .message(msg)
    }

    /// 14-30-22_15-11-2026  (HH-mm-ss_dd-MM-yyyy, 24-hour)
    nonisolated static func makeStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH-mm-ss_dd-MM-yyyy"
        return f.string(from: Date())
    }

    /// [OriginalName]_Jukto_HH-mm-ss_DD-MM-YYYY
    private func outputTemplate(for m: VideoMetadata, stamp: String) -> String {
        let suffix = "_Jukto_\(stamp)"
        if m.platform == .reddit || m.sniffed {      // no useful title from the stream URL itself
            let safe = m.title.sanitizedFilename.replacingOccurrences(of: "%", with: "%%")
            return "\(safe.isEmpty ? "video" : safe)\(suffix).%(ext)s"
        }
        return "%(title).100B\(suffix).%(ext)s"
    }

    private static func safeCode(_ s: String) -> String? {
        let c = s.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return c.isEmpty ? nil : c
    }

    /// "Max" sorts by highest resolution (8K when the site offers it), then frame rate.
    private func formatArgs(_ o: DownloadOptions, platform: Platform) -> [String] {
        let res = o.resolution == .best ? "res" : "res:\(o.resolution.rawValue)"
        let lang = o.audioTrack.flatMap { $0 == "*" ? nil : Self.safeCode($0) }
        let allAudio = o.audioTrack == "*" && !o.format.isAudio

        var args: [String]
        switch o.format {
        case .mp3:
            let sel = lang.map { "ba[language^=\($0)]/ba/b" } ?? "ba/b"
            args = ["-f", sel, "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        default:
            // One file at the chosen height: take a ready-made single stream when the site has one at exactly that
            // height; otherwise download video + audio in parallel and merge losslessly into ONE file.
            let ext = o.format == .webm ? "webm" : "mp4"
            let single = (o.resolution != .best && !allAudio && lang == nil)
                ? "b[height=\(o.resolution.rawValue)][ext=\(ext)]/" : ""
            let merged = allAudio ? "bv*+mergeall[vcodec=none]/bv*+ba/b"
                : (lang.map { "bv*+ba[language^=\($0)]/bv*+ba/b" } ?? "bv*+ba/b")
            // Finder / QuickTime-playable first (H.264 / HEVC video + AAC sound): such a file needs NO conversion at all.
            // Applies to "Max" and to 1080p and below; an explicit 1440p / 4K / 8K takes the original streams
            // (YouTube only has those as VP9 / AV1), so nothing stands between you and the full resolution.
            let wantNative = (o.format == .mp4 || o.format == .mov) && lang == nil && !allAudio
                && (o.resolution == .best || o.resolution.rawValue <= 1080)
            let nativeV = "bv*[vcodec~='^(avc|h264|hev|hvc)']"
            let native = wantNative ? "\(nativeV)+ba[acodec~='^(mp4a|aac)']/\(nativeV)+ba/" : ""
            let sel = single + native + merged
            switch o.format {
            case .mp4:
                // -S prefers H.264/AAC streams when the site has them, so files are Finder/QuickTime-playable
                // without any re-encoding. If only VP9/AV1 is available, it downloads as-is (no conversion).
                // Instagram also serves VP9/AV1, which Finder and Quick Look (space bar) can't play: H.264 first there.
                let sort = platform == .instagram ? "vcodec:h264,\(res),fps,acodec:aac" : "\(res),fps,vcodec:h264,acodec:aac"
                args = ["-f", sel, "-S", sort, "--merge-output-format", "mp4"]
            case .mov:   // QuickTime needs H.264/HEVC, so codec comes first here
                args = ["-f", sel, "-S", "vcodec:h264,\(res),fps,acodec:aac",
                        "--merge-output-format", "mp4", "--remux-video", "mov"]
            default:
                args = ["-f", sel, "-S", "\(res),fps,vcodec:vp9,acodec:opus", "--merge-output-format", "webm"]
            }
            if allAudio { args += ["--audio-multistreams"] }

            if o.subtitleMode != .off, let code = o.subtitleCode.flatMap(Self.safeCode) {
                args += ["--write-subs"]
                if o.subtitleIsAuto { args += ["--write-auto-subs"] }
                args += ["--sub-langs", code]
                if o.subtitleMode == .embed && o.format != .mov {
                    args += ["--embed-subs", "--sub-format", "srt/vtt/best"]
                } else {                                    // separate .srt / .vtt next to the video
                    args += ["--convert-subs", o.subtitleMode == .vtt ? "vtt" : "srt"]
                }
            }
        }

        switch o.coverMode {
        case .off: break
        case .file: args += ["--write-thumbnail", "--convert-thumbnails", "jpg"]
        case .embed:
            if o.format == .webm { args += ["--write-thumbnail", "--convert-thumbnails", "jpg"] }   // webm can't hold cover art
            else { args += ["--embed-thumbnail", "--convert-thumbnails", "jpg"] }
        }
        return args
    }

    /// Seconds from an ffmpeg stats line (`… time=00:00:12.34 …`).
    private static func ffmpegSeconds(_ line: String) -> Double? {
        guard let r = line.range(of: "time=") else { return nil }
        let p = line[r.upperBound...].prefix(while: { !$0.isWhitespace }).split(separator: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let s = Double(p[2]), h >= 0 else { return nil }
        return h * 3600 + m * 60 + s
    }

    /// Bytes from an ffmpeg stats line (`… size=   1536kB …`).
    private static func ffmpegBytes(_ line: String) -> Double? {
        guard let r = line.range(of: "size=") else { return nil }
        let tok = line[r.upperBound...].drop(while: { $0 == " " }).prefix(while: { !$0.isWhitespace })
        let digits = tok.prefix(while: { $0.isNumber })
        guard let n = Double(digits) else { return nil }
        let unit = tok.dropFirst(digits.count).lowercased()
        if unit.hasPrefix("k") { return n * 1024 }
        if unit.hasPrefix("m") { return n * 1_048_576 }
        if unit.hasPrefix("g") { return n * 1_073_741_824 }
        return n
    }

    private static func speedText(_ bps: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }
    private static func sizeText(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func parseProgress(_ line: String, meter: SpeedMeter) -> ProgressUpdate? {
        let p = line.split(separator: " ").map(String.init)
        guard p.count >= 6 else { return nil }
        let downloaded = Double(p[1]), total = Double(p[2]) ?? Double(p[3])
        // yt-dlp sometimes has no speed / ETA for a line: work them out so the status never goes blank.
        var speed = Double(p[4])
        if speed == nil, let d = downloaded { speed = meter.update(bytes: d) }
        var eta = Double(p[5])
        if eta == nil, let t = total, let d = downloaded, let s = speed, s > 0, t > d { eta = (t - d) / s }
        var fraction: Double?
        if let d = downloaded, let t = total, t > 0 { fraction = min(0.99, d / t) }
        return ProgressUpdate(fraction: fraction,
                              speed: speed.map(speedText) ?? "",
                              eta: eta.map { $0.timecode } ?? "",
                              size: downloaded.map(sizeText) ?? "")
    }
}
