import Foundation
import Combine

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case mp4, mov, webm, mp3
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var isAudio: Bool { self == .mp3 }
}

/// `best` = highest resolution the site offers (up to 8K).
enum Resolution: Int, CaseIterable, Codable, Identifiable {
    case best = 0
    case p4320 = 4320, p2160 = 2160, p1440 = 1440, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .best: return "Max"
        case .p4320: return "8K"
        case .p2160: return "4K"
        default: return "\(rawValue)p"
        }
    }
}

enum SubtitleMode: String, Codable, CaseIterable { case off, embed, srt, vtt }
enum CoverMode: String, Codable, CaseIterable { case off, file, embed }

struct DownloadOptions: Codable, Equatable {
    var format: OutputFormat = .mp4
    var resolution: Resolution = .best
    var targetSizeMB: Int? = nil
    var clipEnabled = false
    var clipStart: Double = 0
    var clipEnd: Double = 0
    var coverMode: CoverMode = .off
    var subtitleMode: SubtitleMode = .off
    var subtitleCode: String? = nil
    var subtitleIsAuto = false
    /// nil = site default, "*" = every audio track, otherwise a language code.
    var audioTrack: String? = nil

    var clipRange: ClosedRange<Double>? {
        clipEnabled && clipEnd > clipStart ? clipStart...clipEnd : nil
    }
}

enum DownloadStatus: Equatable {
    case queued, downloading, compressing, completed
    case failed(String)
    case cancelled

    var isActive: Bool { self == .downloading || self == .compressing }
    var isFinished: Bool {
        switch self { case .completed, .failed, .cancelled: true; default: false }
    }
}

struct ProgressUpdate: Sendable {
    var fraction: Double?
    var speed: String
    var eta: String
    /// Bytes downloaded so far, as text (shown when the total size is unknown).
    var size: String = ""
}

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    nonisolated let id: UUID
    /// Fixed per download, so a retry or a resume after a restart continues the same partial file.
    let stamp: String
    let metadata: VideoMetadata
    let options: DownloadOptions
    let directory: URL

    var handle = ProcessHandle()
    var task: Task<Void, Never>?
    /// Set when the download failed because the site wants a sign-in.
    var authPlatform: Platform?

    @Published var status: DownloadStatus = .queued
    @Published var progress: Double = 0
    @Published var speed = ""
    @Published var eta = ""
    @Published var sizeText = ""
    @Published var outputURL: URL?
    @Published var phaseNote: String?

    init(metadata: VideoMetadata, options: DownloadOptions, directory: URL,
         id: UUID = UUID(), stamp: String = YTDLPService.makeStamp()) {
        self.metadata = metadata; self.options = options; self.directory = directory
        self.id = id; self.stamp = stamp
    }

    func apply(_ u: ProgressUpdate) {
        guard status == .downloading else { return }
        if let f = u.fraction { progress = max(progress, f) }   // monotonic across video+audio streams
        // Keep the last known values when a line has none, so the status never blinks out.
        if !u.speed.isEmpty { speed = u.speed }
        if !u.eta.isEmpty { eta = u.eta }
        if !u.size.isEmpty { sizeText = u.size }
    }

    func resetForRetry() {
        status = .queued; progress = 0; speed = ""; eta = ""; sizeText = ""; outputURL = nil; phaseNote = nil
        authPlatform = nil
        handle = ProcessHandle()
    }
}
