import AppKit
import UserNotifications

/// Sound + banner when a download finishes. (Apple's iOS tones aren't available on macOS, so any macOS system sound can be chosen.)
enum CompletionFeedback {
    static let soundKey = "completionSound"

    static var availableSounds: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return names.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    @MainActor static func play() {
        let name = UserDefaults.standard.string(forKey: soundKey) ?? "Glass"
        guard name != "None" else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Asks for notification permission the first time a download actually finishes — not at launch.
    static func notify(title: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = "Download complete"
            c.body = title
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}
