import Foundation

enum FFmpegService {
    static func version() async -> String? {
        let out = LockedLines()
        guard let code = try? await runProcess(JuktoEnvironment.ffmpegPath, ["-version"], onOut: { out.append($0) }),
              code == 0, let first = out.lines.first else { return nil }
        let parts = first.split(separator: " ")
        return parts.count >= 3 ? String(parts[2]) : first
    }

    fileprivate static func rational(_ s: Substring) -> Double? {
        let p = s.split(separator: "/")
        guard let n = p.first.flatMap({ Double($0) }) else { return nil }
        if p.count == 2, let d = Double(p[1]), d != 0 { return n / d }
        return p.count == 1 ? n : nil
    }

    /// QuickTime, Finder and Quick Look only play H.264 or HEVC (tagged hvc1) video with AAC / MP3 / AC-3 sound inside
    /// MP4 and MOV. The top resolutions on YouTube and some other sites come as VP9 / AV1 with Opus sound: they save
    /// fine but do not play. Files that already play are left alone (no work at all); an HEVC file with the wrong tag
    /// is only relabelled (instant); anything else is converted with the Mac's hardware encoder (x264 as fallback).
    /// If the conversion fails, the original file is kept.
    static func makePlayableIfNeeded(input: URL, format: OutputFormat, handle: ProcessHandle,
                                     onStart: @escaping @Sendable () -> Void,
                                     onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard format == .mp4 || format == .mov else { return input }
        guard let pr = await probe(input), let vcodec = pr.vcodec else { return input }
        let acodec = pr.acodec

        let videoOK = vcodec == "h264" || vcodec == "hevc"
        let audioOK = acodec == nil || ["aac", "mp3", "ac3", "eac3", "alac"].contains(acodec ?? "")
        let wrongTag = vcodec == "hevc" && pr.vtag != nil && pr.vtag != "hvc1"
        if videoOK && audioOK && !wrongTag { return input }

        guard let dur = pr.formatDur, dur > 0 else { return input }
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ffmpegPath)
        onStart()

        var rateArgs: [String] = []
        if !videoOK, let fr = pr.frameRate, fr.variable {
            rateArgs = ["-fps_mode:v:0", "cfr", "-r:v:0", String(format: "%.3f", fr.fps)]
        }
        let videoAttempts: [[String]]
        if videoOK {
            videoAttempts = [vcodec == "hevc" ? ["-tag:v:0", "hvc1"] : []]
        } else {
            videoAttempts = [
                ["-c:v:0", "hevc_videotoolbox", "-q:v", "65", "-tag:v:0", "hvc1"] + rateArgs,
                ["-c:v:0", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"] + rateArgs
            ]
        }
        let audioArgs = audioOK ? [] : ["-c:a", "aac", "-b:a", "192k"]

        for vArgs in videoAttempts {
            let tmp = input.deletingLastPathComponent()
                .appendingPathComponent(".jukto-\(UUID().uuidString).\(format.rawValue)")
            let args = ["-y", "-i", input.path, "-map", "0:v", "-map", "0:a?", "-map", "0:s?", "-c", "copy"]
                + vArgs + audioArgs + ["-c:s", "mov_text", "-movflags", "+faststart",
                "-progress", "pipe:1", "-nostats", tmp.path]
            let code = try await runProcess(JuktoEnvironment.ffmpegPath, args, handle: handle, onOut: { line in
                if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst("out_time_us=".count)) {
                    onProgress(min(0.99, us / 1_000_000 / dur))
                }
            })
            if handle.isCancelled { try? FileManager.default.removeItem(at: tmp); throw CancellationError() }
            if code == 0 {
                _ = try FileManager.default.replaceItemAt(input, withItemAt: tmp)
                return input
            }
            try? FileManager.default.removeItem(at: tmp)
        }
        return input     // couldn't convert: keep the original rather than failing the download
    }

    /// If (and only if) the source has a variable frame rate, converts it to constant frame rate at the
    /// source's own nominal fps. On the vast majority of downloads (already CFR) this does nothing and
    /// costs only one quick ffprobe call. Hardware encoder first (fast), x264 as a fallback.
    static func fixFrameRateIfNeeded(input: URL, format: OutputFormat, handle: ProcessHandle,
                                     onStart: @escaping @Sendable () -> Void,
                                     onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard format == .mp4 || format == .mov else { return input }
        guard let pr = await probe(input), let fr = pr.frameRate, fr.variable else { return input }
        guard let dur = pr.formatDur, dur > 0 else { return input }
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ffmpegPath)
        onStart()

        let videoCodec = pr.vcodec
        let videoAttempts: [[String]] = videoCodec == "hevc"
            ? [["-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1"],
               ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]]
            : [["-c:v", "h264_videotoolbox", "-q:v", "65"],
               ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]]
        let rateArgs = ["-fps_mode", "cfr", "-r", String(format: "%.3f", fr.fps)]

        for vArgs in videoAttempts {
            let tmp = input.deletingLastPathComponent()
                .appendingPathComponent(".jukto-\(UUID().uuidString).\(format.rawValue)")
            let args = ["-y", "-i", input.path, "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"]
                + vArgs + rateArgs + ["-c:a", "copy", "-c:s", "mov_text",
                "-progress", "pipe:1", "-nostats", tmp.path]
            let code = try await runProcess(JuktoEnvironment.ffmpegPath, args, handle: handle, onOut: { line in
                if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst("out_time_us=".count)) {
                    onProgress(min(0.99, us / 1_000_000 / dur))
                }
            })
            if handle.isCancelled { try? FileManager.default.removeItem(at: tmp); throw CancellationError() }
            if code == 0 {
                _ = try FileManager.default.replaceItemAt(input, withItemAt: tmp)
                return input
            }
            try? FileManager.default.removeItem(at: tmp)
        }
        return input     // couldn't convert: keep the original rather than failing the download
    }

    // MARK: one-shot probe (a single ffprobe call instead of several)
    struct MediaProbe {
        var vcodec: String?, acodec: String?, vtag: String?
        var rFps: Double?, avgFps: Double?
        var vStart: Double?, aStart: Double?, vDur: Double?, aDur: Double?
        var formatDur: Double?
        var frameRate: (variable: Bool, fps: Double)? {
            guard let a = rFps, let b = avgFps, a > 0, b > 0 else { return nil }
            return (abs(a - b) / max(a, b) > 0.02, min(a, b))
        }
    }

    static func probe(_ url: URL) async -> MediaProbe? {
        let out = LockedLines()
        guard let code = try? await runProcess(JuktoEnvironment.ffprobePath,
              ["-v", "error", "-show_entries",
               "stream=codec_type,codec_name,codec_tag_string,r_frame_rate,avg_frame_rate,start_time,duration:format=duration",
               "-of", "json", url.path],
              onOut: { out.append($0) }), code == 0,
              let data = out.lines.joined(separator: "\n").data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func num(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let s = v as? String { return Double(s) }
            return nil
        }
        var p = MediaProbe()
        if let f = root["format"] as? [String: Any] { p.formatDur = num(f["duration"]) }
        for s in (root["streams"] as? [[String: Any]]) ?? [] {
            switch s["codec_type"] as? String {
            case "video" where p.vcodec == nil:
                p.vcodec = s["codec_name"] as? String
                p.vtag = s["codec_tag_string"] as? String
                p.rFps = (s["r_frame_rate"] as? String).flatMap { rational(Substring($0)) }
                p.avgFps = (s["avg_frame_rate"] as? String).flatMap { rational(Substring($0)) }
                p.vStart = num(s["start_time"]); p.vDur = num(s["duration"])
            case "audio" where p.acodec == nil:
                p.acodec = s["codec_name"] as? String
                p.aStart = num(s["start_time"]); p.aDur = num(s["duration"])
            default: break
            }
        }
        return p
    }

    /// Cleans up a trimmed clip so it has no black / frozen / silent parts. The cut itself is a fast stream copy, which
    /// starts at the keyframe BEFORE the requested start, so video and sound can begin at different moments and the
    /// container can be longer than the clip. One ffprobe call checks this; a clip that is already clean is not touched.
    /// 1) lengths and starts agree → nothing to do. 2) otherwise the common part of video and sound is cut out
    /// frame-exactly: video re-encoded with the Mac's hardware encoder (seconds for a clip), sound copied.
    /// Any failure keeps the original file.
    static func cleanClip(input: URL, expected: Double, format: OutputFormat, handle: ProcessHandle,
                          onStart: @escaping @Sendable () -> Void) async -> URL {
        guard expected > 0, let p = await probe(input), let fmtDur = p.formatDur else { return input }
        let starts = [p.vStart, p.aStart].compactMap { $0 }
        let fileStart = starts.min() ?? 0
        let lo = max(starts.max() ?? 0, fileStart)
        var ends: [Double] = []
        if let s = p.vStart, let d = p.vDur { ends.append(s + d) }
        if let s = p.aStart, let d = p.aDur { ends.append(s + d) }
        let hi = min(ends.min() ?? (fileStart + fmtDur), lo + expected)

        let startGap = abs((p.vStart ?? lo) - (p.aStart ?? lo))
        let endGap = ends.count == 2 ? abs(ends[0] - ends[1]) : 0
        let tooLong = fmtDur > expected + 0.75
        guard startGap > 0.08 || endGap > 0.3 || tooLong else { return input }
        guard hi - lo > 0.2, (try? JuktoEnvironment.ensureExecutable(JuktoEnvironment.ffmpegPath)) != nil else { return input }
        onStart()

        let ext = input.pathExtension.lowercased()
        let ss = String(format: "%.3f", max(0, lo - fileStart)), t = String(format: "%.3f", hi - lo)
        let isMP4 = ["mp4", "mov", "m4a"].contains(ext)
        let hevc = p.vcodec == "hevc"
        let videoAttempts: [[String]]
        if p.vcodec == nil || !(format == .mp4 || format == .mov) {
            videoAttempts = [["-c", "copy"]]                       // sound only / webm: trim by copy
        } else {
            videoAttempts = [
                hevc ? ["-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1"] : ["-c:v", "h264_videotoolbox", "-q:v", "65"],
                ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
            ]
        }
        for v in videoAttempts {
            let tmp = input.deletingLastPathComponent().appendingPathComponent(".jukto-\(UUID().uuidString).\(ext)")
            var args = ["-y", "-i", input.path, "-map", "0:v:0?", "-map", "0:a?"] + v
            if v.first != "-c" { args += ["-c:a", "copy"] }
            args += ["-ss", ss, "-t", t, "-avoid_negative_ts", "make_zero", "-shortest"]
            if isMP4 { args += ["-movflags", "+faststart"] }
            args.append(tmp.path)
            let code = try? await runProcess(JuktoEnvironment.ffmpegPath, args, handle: handle)
            if handle.isCancelled { try? FileManager.default.removeItem(at: tmp); return input }
            if code == 0, (try? FileManager.default.replaceItemAt(input, withItemAt: tmp)) != nil { return input }
            try? FileManager.default.removeItem(at: tmp)
        }
        return input
    }

    static func duration(of url: URL) async -> Double? {
        let out = LockedLines()
        guard let code = try? await runProcess(JuktoEnvironment.ffprobePath,
              ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path],
              onOut: { out.append($0) }), code == 0 else { return nil }
        return out.lines.first.flatMap(Double.init)
    }

    /// Re-encodes `input` to roughly `targetMB` using a computed bitrate. Replaces the original file.
    static func compress(input: URL, format: OutputFormat, targetMB: Int,
                         handle: ProcessHandle,
                         onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try JuktoEnvironment.ensureExecutable(JuktoEnvironment.ffmpegPath)
        let size = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int64) ?? nil
        let targetBytes = Int64(targetMB) * 1_048_576
        if let size, size <= targetBytes { return input }
        guard let dur = await duration(of: input), dur > 0 else { return input }

        let totalBitrate = Double(targetBytes) * 8 * 0.93 / dur   // 7% muxing headroom
        let tmp = input.deletingLastPathComponent()
            .appendingPathComponent(".clip-\(UUID().uuidString).\(format.rawValue)")

        var args = ["-y", "-i", input.path, "-progress", "pipe:1", "-nostats"]
        switch format {
        case .mp3:
            let kbps = Int(min(320, max(32, totalBitrate / 1000)))
            args += ["-vn", "-c:a", "libmp3lame", "-b:a", "\(kbps)k"]
        case .mp4, .mov:
            let v = Int(max(100_000, totalBitrate - 128_000))
            args += ["-c:v", "libx264", "-preset", "medium", "-b:v", "\(v)", "-maxrate", "\(Int(Double(v) * 1.5))",
                     "-bufsize", "\(v * 2)", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
        case .webm:
            let v = Int(max(100_000, totalBitrate - 128_000))
            args += ["-c:v", "libvpx-vp9", "-b:v", "\(v)", "-deadline", "good", "-cpu-used", "4",
                     "-c:a", "libopus", "-b:a", "128k"]
        }
        args.append(tmp.path)

        let errors = LockedLines()
        let code = try await runProcess(JuktoEnvironment.ffmpegPath, args, handle: handle, onOut: { line in
            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst("out_time_us=".count)) {
                onProgress(min(0.99, us / 1_000_000 / dur))
            }
        }, onErr: { errors.append($0) })

        if handle.isCancelled { try? FileManager.default.removeItem(at: tmp); throw CancellationError() }
        guard code == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw JuktoError.message(errors.lastError ?? "ffmpeg exited with code \(code)")
        }
        _ = try FileManager.default.replaceItemAt(input, withItemAt: tmp)
        return input
    }
}
