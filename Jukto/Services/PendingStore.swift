import Foundation

/// A download that has not finished, kept on disk so it can be continued after the app is closed or crashes.
/// Streams found by the capture browser are not kept (their session cookies are never written to disk).
struct PendingJob: Codable, Identifiable {
    var id: UUID
    var stamp: String
    var directory: String
    var options: DownloadOptions
    var title: String
    var uploader: String?
    var duration: Double?
    var thumbnail: String?
    var platform: Platform
    var originalURL: String
    var downloadURL: String
    var maxHeight: Int?
    var impersonate: Bool
    var browser: String?
}

@MainActor
final class PendingStore {
    private(set) var jobs: [PendingJob] = []
    private let fileURL = JuktoConstants.supportDirectory.appendingPathComponent("pending.json")

    init() {
        if let data = try? Data(contentsOf: fileURL) { jobs = (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? [] }
    }

    func upsert(_ item: DownloadItem) {
        let m = item.metadata
        guard !m.sniffed else { return }
        let job = PendingJob(id: item.id, stamp: item.stamp, directory: item.directory.path, options: item.options,
                             title: m.title, uploader: m.uploader, duration: m.duration,
                             thumbnail: m.thumbnail?.absoluteString, platform: m.platform,
                             originalURL: m.originalURL.absoluteString, downloadURL: m.downloadURL.absoluteString,
                             maxHeight: m.maxHeight, impersonate: m.impersonate, browser: m.browser)
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i] = job } else { jobs.append(job) }
        save()
    }

    func remove(_ id: UUID) {
        guard jobs.contains(where: { $0.id == id }) else { return }
        jobs.removeAll { $0.id == id }
        save()
    }

    func metadata(for job: PendingJob) -> VideoMetadata? {
        guard let o = URL(string: job.originalURL), let d = URL(string: job.downloadURL) else { return nil }
        var md = VideoMetadata(title: job.title, uploader: job.uploader, duration: job.duration,
                               thumbnail: job.thumbnail.flatMap(URL.init(string:)), platform: job.platform,
                               originalURL: o, downloadURL: d, maxHeight: job.maxHeight)
        md.impersonate = job.impersonate; md.browser = job.browser
        return md
    }

    private func save() {
        if let data = try? JSONEncoder().encode(jobs) { try? data.write(to: fileURL, options: .atomic) }
    }
}
