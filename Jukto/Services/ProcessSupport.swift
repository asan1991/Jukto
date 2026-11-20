import Foundation

enum JuktoError: LocalizedError {
    case message(String)
    case authRequired(Platform, String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .authRequired(let p, _): return "Sign in to \(p.displayName) to continue."
        }
    }
}

enum JuktoEnvironment {
    /// A component updated in-app is used only if its SHA-256 matches the record kept in the Keychain.
    static var ytdlpPath: String { ComponentStore.overridePath("yt-dlp") ?? JuktoConstants.binPath + "/yt-dlp" }
    static var ffmpegPath: String { ComponentStore.overridePath("ffmpeg") ?? JuktoConstants.binPath + "/ffmpeg" }
    static var ffprobePath: String { ComponentStore.overridePath("ffprobe") ?? JuktoConstants.binPath + "/ffprobe" }
    static var ffmpegDirectory: String {
        (ComponentStore.overridePath("ffmpeg") != nil && ComponentStore.overridePath("ffprobe") != nil)
            ? ComponentStore.binDir.path : JuktoConstants.binPath
    }

    static var environment: [String: String] {
        // Drop variables that could inject code into child processes.
        var env = ProcessInfo.processInfo.environment.filter { k, _ in
            !(k.hasPrefix("DYLD_") || k.hasPrefix("LD_") || k.hasPrefix("PYTHON"))
        }
        let extra = ([JuktoConstants.binPath] + JuktoConstants.homebrewPaths).joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    static func ensureExecutable(_ path: String) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw JuktoError.message("Missing \((path as NSString).lastPathComponent). Reinstall Jukto from the original package.")
        }
    }
}

/// Cancellation: set the flag FIRST, then terminate the process.
final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func attach(_ p: Process) { lock.lock(); process = p; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
}

final class OutputPathHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _path: String?
    var path: String? {
        get { lock.lock(); defer { lock.unlock() }; return _path }
        set { lock.lock(); _path = newValue; lock.unlock() }
    }
}

final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func append(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock(); _lines.append(t); lock.unlock()
    }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    var lastError: String? {
        let all = lines
        if let e = all.last(where: { $0.hasPrefix("ERROR") }) {
            return e.replacingOccurrences(of: "ERROR: ", with: "")
        }
        return all.last
    }
}

final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: @Sendable (String) -> Void
    init(_ onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        var out: [String] = []
        lock.lock()
        buffer.append(data)
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            out.append(String(decoding: buffer[buffer.startIndex..<idx], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...idx)
        }
        lock.unlock()
        out.forEach(onLine)
    }

    func flush() {
        lock.lock(); let rest = buffer; buffer = Data(); lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self)) }
    }
}

/// Runs a process, streaming stdout/stderr line by line. Returns the exit status.
@discardableResult
func runProcess(_ executable: String,
                _ arguments: [String],
                handle: ProcessHandle? = nil,
                onOut: @escaping @Sendable (String) -> Void = { _ in },
                onErr: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Int32 {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = JuktoEnvironment.environment
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        let outSplit = LineSplitter(onOut), errSplit = LineSplitter(onErr)

        out.fileHandleForReading.readabilityHandler = { h in outSplit.feed(h.availableData) }
        err.fileHandleForReading.readabilityHandler = { h in errSplit.feed(h.availableData) }

        p.terminationHandler = { proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            outSplit.feed(out.fileHandleForReading.readDataToEndOfFile()); outSplit.flush()
            errSplit.feed(err.fileHandleForReading.readDataToEndOfFile()); errSplit.flush()
            cont.resume(returning: proc.terminationStatus)
        }

        handle?.attach(p)
        do {
            try p.run()
            if handle?.isCancelled == true { p.terminate() }
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            cont.resume(throwing: error)
        }
    }
}

/// Lets at most ~4 progress updates per second through. With 16 parallel fragments yt-dlp prints hundreds of
/// progress lines a second; re-rendering the UI for each one was a big CPU cost during downloads.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func shouldEmit(force: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if force || now.timeIntervalSince(last) >= 0.25 { last = now; return true }
        return false
    }
}

/// Works out a download speed (bytes/s, smoothed) from a growing byte count, for lines that carry no speed of their own.
final class SpeedMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBytes = 0.0, ema = 0.0
    private var lastTime = Date.distantPast
    func update(bytes: Double) -> Double? {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard lastTime != .distantPast else { lastBytes = bytes; lastTime = now; return nil }
        let dt = now.timeIntervalSince(lastTime)
        guard dt >= 0.5 else { return ema > 0 ? ema : nil }
        let inst = max(0, bytes - lastBytes) / dt
        ema = ema == 0 ? inst : ema * 0.7 + inst * 0.3
        lastBytes = bytes; lastTime = now
        return ema > 0 ? ema : nil
    }
}
