import Foundation
import CryptoKit

enum AppChecksum {
    /// Which build this is: "AppleSilicon", "Intel" (the two downloads) or "Universal" (a build for both CPUs).
    /// It is printed next to the hash so it is easy to find the matching line in the release's checksum file.
    static var variant: String {
        if let exe = Bundle.main.executableURL, let fh = try? FileHandle(forReadingFrom: exe) {
            defer { try? fh.close() }
            if let head = try? fh.read(upToCount: 4), [UInt8](head) == [0xCA, 0xFE, 0xBA, 0xBE] { return "Universal" }
        }
        #if arch(arm64)
        return "AppleSilicon"
        #else
        return "Intel"
        #endif
    }

    /// SHA-256 of the app itself: its main executable plus the code-signature manifest. Computed only on click.
    static func compute() throws -> String {
        let bundle = Bundle.main
        guard let exe = bundle.executableURL else { throw JuktoError.message("Couldn't locate the app.") }
        var files = [exe]
        let seal = bundle.bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        if FileManager.default.fileExists(atPath: seal.path) { files.append(seal) }
        var hasher = SHA256()
        for url in files {
            let fh = try FileHandle(forReadingFrom: url)
            defer { try? fh.close() }
            while true {
                let chunk = try fh.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
