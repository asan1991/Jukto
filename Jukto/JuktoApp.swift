import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let main = MainViewModel()
    let downloads = DownloadViewModel()
    let monitor = ClipboardMonitor()
    let updates = UpdateService()
    let auth = AuthCoordinator()
    @Published var showDonation = false
    /// True when the thank-you card was opened by Cmd+Q / Quit, so closing it quits the app.
    var quitRequested = false
    var quitConfirmed = false
    private var bag = Set<AnyCancellable>()

    private init() {
        UserDefaults.standard.register(defaults: [
            JuktoConstants.Keys.clipboardMonitoring: true,
            JuktoConstants.Keys.autoAnalyze: true,
            JuktoConstants.Keys.showThanksOnClose: true,
            JuktoConstants.Keys.resumeOnLaunch: true,
            JuktoConstants.Keys.textScale: 1.0,
            JuktoConstants.Keys.defaultResolution: Resolution.best.rawValue
        ])
        monitor.$detectedURL.compactMap { $0 }
            .sink { [weak self] in self?.main.receiveClipboard($0) }.store(in: &bag)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.syncMonitor(); self?.applyAppearance() }.store(in: &bag)

        downloads.onItemCompleted = { item in
            CompletionFeedback.play()
            CompletionFeedback.notify(title: item.metadata.title)
            StatusBarController.shared.celebrate()
        }

        // After a successful sign-in: retry the analysis and any downloads that were waiting for it.
        auth.onLoggedIn = { [weak self] platform in
            guard let self else { return }
            if self.main.metadata == nil,
               !self.main.urlText.trimmingCharacters(in: .whitespaces).isEmpty { self.main.analyze() }
            self.downloads.retryAuthFailed(platform)
        }
        syncMonitor()
        applyAppearance()
    }

    /// Light / dark theme chosen with the day-night switch ("system" follows macOS).
    private func applyAppearance() {
        let mode = UserDefaults.standard.string(forKey: JuktoConstants.Keys.appearance) ?? "system"
        let target: NSAppearance? = mode == "light" ? NSAppearance(named: .aqua) : mode == "dark" ? NSAppearance(named: .darkAqua) : nil
        if NSApplication.shared.appearance?.name != target?.name { NSApplication.shared.appearance = target }
    }

    private func syncMonitor() {
        if UserDefaults.standard.bool(forKey: JuktoConstants.Keys.clipboardMonitoring) { monitor.start() } else { monitor.stop() }
    }
}

enum MainWindow {
    @MainActor static func hide() {
        NSApp.windows.first { $0.identifier?.rawValue == JuktoConstants.mainWindowIdentifier }?.orderOut(nil)
    }
    @MainActor static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let win = NSApp.windows.first { $0.identifier?.rawValue == JuktoConstants.mainWindowIdentifier }
        win?.makeKeyAndOrderFront(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ComponentStore.resetIfAppUpdated()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let state = AppState.shared
            StatusBarController.shared.install(state: state)
            state.downloads.resumePending()          // continue what was not finished last time
            // ⌘= (the unshifted "+" key) also enlarges; ⌘+ / ⌘− / ⌘0 are in the View menu.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                if e.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                   e.charactersIgnoringModifiers == "=" { MainActor.assumeIsolated { JuktoZoom.zoomIn() }; return nil }
                return e
            }
            // No automatic update check — yt-dlp/ffmpeg are only checked when the person asks
            // (clicking the version text, or the Settings button), to keep launch fast and quiet.
        }
    }

    /// Cmd+Q / "Quit Jukto": show the thank-you card first; closing it (or pressing Cmd+Q again) quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { () -> NSApplication.TerminateReply in
            let state = AppState.shared
            guard UserDefaults.standard.bool(forKey: JuktoConstants.Keys.showThanksOnClose),
                  !state.showDonation, !state.quitConfirmed else { return .terminateNow }
            state.quitRequested = true
            state.showDonation = true
            MainWindow.show()
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.downloads.prepareForQuit() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in MainWindow.show() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct JuktoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window(JuktoConstants.appName, id: JuktoConstants.mainWindowID) {
            ZoomContainer {
                ContentView()
                    .environmentObject(state.main)
                    .environmentObject(state.downloads)
                    .environmentObject(state.updates)
                    .environmentObject(state.monitor)
                    .environmentObject(state.auth)
                    .environmentObject(state)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 620, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Paste & Analyze Link") { state.main.paste(analyze: true); MainWindow.show() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Increase Text Size") { JuktoZoom.zoomIn() }.keyboardShortcut("+", modifiers: .command)
                Button("Decrease Text Size") { JuktoZoom.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("Actual Text Size") { JuktoZoom.reset() }.keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Snap to Left Half") { JuktoZoom.snap(.left) }.keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                Button("Snap to Right Half") { JuktoZoom.snap(.right) }.keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                Button("Fill Screen") { JuktoZoom.snap(.fill) }.keyboardShortcut(.upArrow, modifiers: [.control, .command])
                Button("Center Window") { JuktoZoom.snap(.center) }.keyboardShortcut(.downArrow, modifiers: [.control, .command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state.updates)
                .environmentObject(state.auth)
        }
    }
}
