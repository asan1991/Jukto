import AppKit
import Combine

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published var detectedURL: URL?
    @Published private(set) var isRunning = false
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: JuktoConstants.clipboardPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.5          // lets macOS coalesce wake-ups (lower power)
        isRunning = true
    }

    /// The app itself just changed the clipboard (e.g. copied a link): don't treat it as a newly copied video link.
    func markHandled() { lastChange = NSPasteboard.general.changeCount }

    func stop() { timer?.invalidate(); timer = nil; isRunning = false }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if let s = pb.string(forType: .string), let url = URLDetector.firstURL(in: s) { detectedURL = url }
    }
}
