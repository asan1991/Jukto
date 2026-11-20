import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var metadata: VideoMetadata?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var options = DownloadOptions()
    @Published var isDropTargeted = false
    @Published var captureRequest: CaptureRequest?
    private(set) var lastURL: URL?
    @Published var saveDirectory: URL {
        didSet { UserDefaults.standard.set(saveDirectory.path, forKey: JuktoConstants.Keys.saveDirectory) }
    }

    private var analyzeTask: Task<Void, Never>?
    private var defaults: UserDefaults { .standard }

    init() {
        let d = UserDefaults.standard
        if let p = d.string(forKey: JuktoConstants.Keys.saveDirectory) {
            saveDirectory = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            saveDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
        }
        if let f = d.string(forKey: JuktoConstants.Keys.defaultFormat).flatMap(OutputFormat.init(rawValue:)) { options.format = f }
        let r = d.integer(forKey: JuktoConstants.Keys.defaultResolution)
        if let res = Resolution(rawValue: r) { options.resolution = res }
    }

    var autoAnalyze: Bool { defaults.bool(forKey: JuktoConstants.Keys.autoAnalyze) }

    func paste(analyze: Bool? = nil) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if analyze ?? autoAnalyze { self.analyze() }
    }

    func receiveClipboard(_ url: URL) {
        guard urlText.isEmpty, !isAnalyzing, metadata == nil else { return }
        urlText = url.absoluteString
        if autoAnalyze { analyze() }
    }

    /// `userInitiated`: the person pressed Analyze (or Return / dropped a link). If the link has no particular video
    /// in it, the page opens straight away so they can pick one; automatic analysis (paste, clipboard) only says so.
    func analyze(userInitiated: Bool = false) {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLDetector.firstURL(in: trimmed) else {
            errorMessage = "That doesn't look like a link."; return
        }
        lastURL = url
        if !URLDetector.pointsToVideo(url) {
            analyzeTask?.cancel()
            isAnalyzing = false; metadata = nil
            if userInitiated {
                errorMessage = nil
                captureRequest = CaptureRequest(url: url, choosing: true)
            } else {
                errorMessage = "This link has no specific video. Press Analyze to open the page and choose one."
            }
            return
        }
        analyzeTask?.cancel()
        isAnalyzing = true; errorMessage = nil; metadata = nil
        analyzeTask = Task { [weak self] in
            do {
                let md = try await YTDLPService.shared.fetchMetadata(for: url)
                guard let self, !Task.isCancelled else { return }
                self.metadata = md
                self.options.clipEnabled = false
                self.options.subtitleMode = .off; self.options.subtitleCode = nil; self.options.audioTrack = nil
                self.options.clipStart = 0
                self.options.clipEnd = md.duration ?? 0
                if let mh = md.maxHeight, self.options.resolution != .best, self.options.resolution.rawValue > mh {
                    self.options.resolution = Resolution.allCases.first { $0 != .best && $0.rawValue <= mh } ?? .p360
                }
            } catch {
                if error is CancellationError {
                    // superseded by a newer analyze
                } else if case JuktoError.authRequired(let p, _) = error {
                    self?.errorMessage = "Sign in to \(p.displayName) to continue."
                    AppState.shared.auth.requestLogin(p)
                    MainWindow.show()
                } else {
                    self?.errorMessage = error.localizedDescription
                }
            }
            self?.isAnalyzing = false
        }
    }

    /// True when analysis failed and the capture browser may still find the video on the page.
    var canCapture: Bool {
        guard let u = lastURL, errorMessage != nil, metadata == nil, !isAnalyzing else { return false }
        return Platform.detect(u) == .unknown
    }

    func useSniffed(_ md: VideoMetadata) {
        errorMessage = nil; metadata = md
        options.clipEnabled = false; options.clipStart = 0; options.clipEnd = md.duration ?? 0
        options.subtitleMode = .off; options.subtitleCode = nil; options.audioTrack = nil
    }

    func reset() {
        analyzeTask?.cancel()
        urlText = ""; metadata = nil; errorMessage = nil; isAnalyzing = false
        options.clipEnabled = false; options.clipStart = 0; options.clipEnd = 0
        options.subtitleMode = .off; options.subtitleCode = nil; options.audioTrack = nil
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        if p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.urlText = url.absoluteString; self?.analyze(userInitiated: true) }
            }
            return true
        }
        if p.canLoadObject(ofClass: NSString.self) {
            _ = p.loadObject(ofClass: NSString.self) { [weak self] s, _ in
                guard let s = s as? String else { return }
                Task { @MainActor in self?.urlText = s; self?.analyze(userInitiated: true) }
            }
            return true
        }
        return false
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory; panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { saveDirectory = url }
    }
}
