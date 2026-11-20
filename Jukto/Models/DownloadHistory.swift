import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var platform: Platform
    var path: String
    var date: Date
    var thumbnail: String?
    var format: String
    /// The page the video came from (older entries have none).
    var sourceURL: String? = nil
}

@MainActor
final class DownloadHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let fileURL = JuktoConstants.supportDirectory.appendingPathComponent("history.json")

    init() { load() }

    func add(_ entry: HistoryEntry) { entries.insert(entry, at: 0); save() }
    func remove(_ entry: HistoryEntry) { entries.removeAll { $0.id == entry.id }; save() }
    func clear() { entries.removeAll(); save() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        entries = (try? dec.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
}
