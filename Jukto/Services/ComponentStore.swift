import Foundation
import CryptoKit

enum Hashing {
    static func sha256(of url: URL) throws -> String {
        var hasher = SHA256()
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        while true {
            let chunk = try fh.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Components (yt-dlp, ffmpeg, ffprobe) updated in-app live in Application Support.
/// Each one's SHA-256 is recorded in the Keychain at install time and re-checked before it is ever executed,
/// so a file swapped on disk by another process is ignored (the bundled copy is used instead).
enum ComponentStore {
    static var binDir: URL { JuktoConstants.supportDirectory.appendingPathComponent("bin", isDirectory: true) }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock(); private var stamps: [String: String] = [:]
        func get(_ k: String) -> String? { lock.lock(); defer { lock.unlock() }; return stamps[k] }
        func set(_ k: String, _ v: String?) { lock.lock(); stamps[k] = v; lock.unlock() }
    }
    private static let cache = Cache()

    private static func account(_ name: String) -> String { "component.\(name)" }

    static func overridePath(_ name: String) -> String? {
        let url = binDir.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        guard let rec = KeychainStore.get(account: account(name)), let expected = String(data: rec, encoding: .utf8) else {
            remove(name); return nil
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = "\(attrs?[.size] ?? 0)|\(String(describing: attrs?[.modificationDate]))|\(String(describing: attrs?[.systemFileNumber]))"
        if cache.get(name) == stamp { return url.path }
        guard let actual = try? Hashing.sha256(of: url), actual == expected else { remove(name); return nil }
        cache.set(name, stamp)
        return url.path
    }

    /// Installs an already-verified download.
    static func install(_ tmp: URL, name: String, signIfNeeded: Bool) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = binDir.appendingPathComponent(".\(name).new")
        let dest = binDir.appendingPathComponent(name)
        try? fm.removeItem(at: staged)
        try fm.moveItem(at: tmp, to: staged)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

        if signIfNeeded {   // Apple Silicon refuses unsigned binaries
            let verify = try await runProcess("/usr/bin/codesign", ["--verify", staged.path])
            if verify != 0 { _ = try await runProcess("/usr/bin/codesign", ["--force", "--sign", "-", staged.path]) }
        }
        let hash = try Hashing.sha256(of: staged)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: staged, to: dest)
        guard KeychainStore.set(Data(hash.utf8), account: account(name)) else {
            remove(name)
            throw JuktoError.message("Couldn't store the integrity record in your Keychain.")
        }
        cache.set(name, nil)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: binDir.appendingPathComponent(name))
        KeychainStore.delete(account: account(name))
        cache.set(name, nil)
    }

    static func removeAll() { ["yt-dlp", "ffmpeg", "ffprobe"].forEach(remove) }

    /// A new app build ships its own (newer) components, so drop older in-app updates.
    static func resetIfAppUpdated() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let key = "lastLaunchedBuild"
        guard UserDefaults.standard.string(forKey: key) != build else { return }
        // Files only — deliberately NO Keychain access at launch (it can stall for seconds or pop a permission
        // prompt before any window appears). Stale integrity records are harmless: an updated component is only
        // trusted if its file exists AND matches its record, and a new update overwrites the record.
        try? FileManager.default.removeItem(at: binDir)
        ComponentUpdater.forgetInstalledFFmpegTag()
        UserDefaults.standard.set(build, forKey: key)
    }
}
