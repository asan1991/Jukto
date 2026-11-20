import AppKit
import Combine

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    /// 0…1 across queued + active downloads; nil when idle. Drives the menu bar arc.
    @Published private(set) var overallProgress: Double?
    let history = DownloadHistory()
    /// Called on the main actor whenever a download finishes successfully.
    var onItemCompleted: ((DownloadItem) -> Void)?

    private var observers: [UUID: AnyCancellable] = [:]
    private var historyObserver: AnyCancellable?
    private let pending = PendingStore()
    /// Set while the app quits, so interrupted downloads stay on the to-continue list.
    private var terminating = false

    init() {
        // Forward history changes so views observing this VM refresh.
        historyObserver = history.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var activeCount: Int { items.filter { $0.status.isActive }.count }
    var pendingCount: Int { items.filter { $0.status == .queued || $0.status.isActive }.count }

    func enqueue(_ metadata: VideoMetadata, options: DownloadOptions, directory: URL) {
        add(DownloadItem(metadata: metadata, options: options, directory: directory))
    }

    private func add(_ item: DownloadItem) {
        pending.upsert(item)
        items.insert(item, at: 0)
        observers[item.id] = item.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshOverall() }
        }
        refreshOverall()
        startNextQueued()
    }

    /// On launch: continue the downloads that were not finished last time (yt-dlp carries on from the partial file).
    /// With the setting off they are listed as interrupted, ready for a manual retry.
    func resumePending() {
        let auto = UserDefaults.standard.bool(forKey: JuktoConstants.Keys.resumeOnLaunch)
        for job in pending.jobs {
            guard !items.contains(where: { $0.id == job.id }), let md = pending.metadata(for: job) else { continue }
            let item = DownloadItem(metadata: md, options: job.options, directory: URL(fileURLWithPath: job.directory),
                                    id: job.id, stamp: job.stamp)
            items.insert(item, at: 0)
            observers[item.id] = item.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshOverall() }
            }
            if !auto { item.status = .failed("Interrupted — press Retry to continue.") }
        }
        refreshOverall()
        startNextQueued()
    }

    /// Stops running downloads when the app quits (they stay on the list and continue next launch).
    func prepareForQuit() {
        terminating = true
        for i in items where !i.status.isFinished { i.handle.cancel() }
    }

    func openSource(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        AppState.shared.monitor.markHandled()
        NSWorkspace.shared.open(url)                      // opens in the default browser
        ToastCenter.shared.show("Link copied to clipboard.", seconds: 1.5)
    }

    /// Called after every enqueue / completion / failure / cancel.
    func startNextQueued() {
        while activeCount < JuktoConstants.maxConcurrentDownloads,
              let next = items.last(where: { $0.status == .queued }) {   // oldest first
            start(next)
        }
        refreshOverall()
    }

    private func start(_ item: DownloadItem) {
        item.status = .downloading
        let handle = item.handle
        item.task = Task { [weak self] in
            do {
                var file = try await YTDLPService.shared.download(
                    metadata: item.metadata, options: item.options,
                    directory: item.directory, stamp: item.stamp, handle: handle
                ) { update in Task { @MainActor in item.apply(update) } }

                if let r = item.options.clipRange {      // trimmed: remove any black / silent / blank part of the clip
                    file = await FFmpegService.cleanClip(
                        input: file, expected: r.upperBound - r.lowerBound, format: item.options.format, handle: handle,
                        onStart: {
                            Task { @MainActor in
                                item.status = .compressing; item.phaseNote = "Cleaning the trimmed clip"
                                item.progress = 0; item.speed = ""; item.eta = ""
                            }
                        })
                }

                // (an MKV saved by the last-resort fallback is left as it is)
                if (item.options.format == .mp4 || item.options.format == .mov),
                   ["mp4", "mov", "m4v"].contains(file.pathExtension.lowercased()) {
                    file = try await FFmpegService.makePlayableIfNeeded(
                        input: file, format: item.options.format, handle: handle,
                        onStart: {
                            Task { @MainActor in
                                item.status = .compressing; item.phaseNote = "Converting for QuickTime"
                                item.progress = 0; item.speed = ""; item.eta = ""
                            }
                        },
                        onProgress: { f in Task { @MainActor in if item.status == .compressing { item.progress = f } } })

                    file = try await FFmpegService.fixFrameRateIfNeeded(
                        input: file, format: item.options.format, handle: handle,
                        onStart: {
                            Task { @MainActor in
                                item.status = .compressing; item.phaseNote = "Fixing frame rate"
                                item.progress = 0; item.speed = ""; item.eta = ""
                            }
                        },
                        onProgress: { f in Task { @MainActor in if item.status == .compressing { item.progress = f } } })
                }

                if let mb = item.options.targetSizeMB, mb > 0 {
                    item.status = .compressing; item.phaseNote = "Compressing to \(mb) MB"
                    item.progress = 0; item.speed = ""; item.eta = ""
                    file = try await FFmpegService.compress(
                        input: file, format: item.options.format, targetMB: mb, handle: handle
                    ) { f in Task { @MainActor in if item.status == .compressing { item.progress = f } } }
                }

                item.outputURL = file
                item.progress = 1
                item.status = .completed
                self?.history.add(HistoryEntry(
                    id: item.id, title: item.metadata.title, platform: item.metadata.platform,
                    path: file.path, date: Date(),
                    thumbnail: item.metadata.thumbnail?.absoluteString, format: item.options.format.rawValue,
                    sourceURL: item.metadata.originalURL.absoluteString))
                self?.pending.remove(item.id)
                self?.onItemCompleted?(item)
            } catch {
                if self?.terminating == true { return }
                if handle.isCancelled || error is CancellationError {
                    item.status = .cancelled
                    self?.pending.remove(item.id)
                } else if case JuktoError.authRequired(let p, _) = error {
                    item.authPlatform = p
                    item.status = .failed("Sign in to \(p.displayName) to download this.")
                    AppState.shared.auth.requestLogin(p)
                    MainWindow.show()
                } else {
                    item.status = .failed(error.localizedDescription)
                }
            }
            self?.startNextQueued()
        }
    }

    func cancel(_ item: DownloadItem) {
        item.handle.cancel()          // sets isCancelled, then terminates the process
        item.status = .cancelled
        pending.remove(item.id)
        startNextQueued()
    }

    func retry(_ item: DownloadItem) {
        item.resetForRetry()
        pending.upsert(item)
        startNextQueued()
    }

    /// After a successful sign-in, re-run downloads that were waiting for it.
    func retryAuthFailed(_ platform: Platform) {
        for item in items where item.authPlatform == platform {
            if case .failed = item.status { item.resetForRetry() }
        }
        startNextQueued()
    }

    func remove(_ item: DownloadItem) {
        if !item.status.isFinished { item.handle.cancel() }
        pending.remove(item.id)
        items.removeAll { $0.id == item.id }
        observers[item.id] = nil
        startNextQueued()
    }

    func clearFinished() {
        for i in items where i.status.isFinished { observers[i.id] = nil; pending.remove(i.id) }
        items.removeAll { $0.status.isFinished }
        refreshOverall()
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func refreshOverall() {
        let live = items.filter { $0.status == .queued || $0.status.isActive }
        guard !live.isEmpty else { overallProgress = nil; return }
        overallProgress = live.map(\.progress).reduce(0, +) / Double(live.count)
    }
}
