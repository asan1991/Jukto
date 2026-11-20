import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var updates: UpdateService
    @EnvironmentObject var auth: AuthCoordinator
    @AppStorage(JuktoConstants.Keys.clipboardMonitoring) private var monitorClipboard = true
    @AppStorage(JuktoConstants.Keys.autoAnalyze) private var autoAnalyze = true
    @AppStorage(JuktoConstants.Keys.defaultFormat) private var defaultFormat = OutputFormat.mp4.rawValue
    @AppStorage(JuktoConstants.Keys.defaultResolution) private var defaultResolution = Resolution.best.rawValue
    @AppStorage(CompletionFeedback.soundKey) private var completionSound = "Glass"
    @AppStorage(JuktoConstants.Keys.showThanksOnClose) private var showThanks = true
    @AppStorage(JuktoConstants.Keys.resumeOnLaunch) private var resumeOnLaunch = true
    @AppStorage(JuktoConstants.Keys.textScale) private var textScale = 1.0

    var body: some View {
        Form {
            Section("Links") {
                Toggle("Watch clipboard for links", isOn: $monitorClipboard)
                Toggle("Analyze links automatically", isOn: $autoAnalyze)
            }
            Section("Defaults") {
                Picker("Format", selection: $defaultFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Resolution", selection: $defaultResolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Appearance") {
                LabeledContent("Theme") { DayNightToggle() }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: Binding(get: { JuktoZoom.clamp(textScale) }, set: { JuktoZoom.set($0) }),
                               in: JuktoZoom.minScale...JuktoZoom.maxScale, step: JuktoZoom.step)
                            .frame(width: 150)
                        Text("\(Int((JuktoZoom.clamp(textScale) * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Also ⌘+ and ⌘− (⌘0 resets).").font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Show the thank-you window when closing", isOn: $showThanks)
                Toggle("Continue unfinished downloads when Jukto opens", isOn: $resumeOnLaunch)
            }
            Section("Notifications") {
                Picker("Completion sound", selection: $completionSound) {
                    Text("None").tag("None")
                    ForEach(CompletionFeedback.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                Button("Preview sound") { CompletionFeedback.play() }
            }
            Section("Accounts") {
                ForEach(Platform.allCases.filter(\.supportsLogin)) { p in
                    HStack {
                        Label(p.displayName, systemImage: p.symbol)
                        Spacer()
                        if auth.isSignedIn(p) {
                            Text("Signed in").font(.caption).foregroundStyle(Color.juktoSuccess)
                            Button("Sign out") { auth.signOut(p) }
                        } else {
                            Button("Sign in…") { auth.requestLogin(p); MainWindow.show() }
                        }
                    }
                }
                Text("Sessions are stored encrypted in your Keychain. Jukto never sees or stores your password.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Components") {
                LabeledContent("yt-dlp", value: updates.currentVersion ?? "—")
                LabeledContent("ffmpeg", value: updates.ffmpegVersion ?? "—")
                HStack {
                    Button("Check for Updates") { Task { await updates.check(silent: false) } }
                        .disabled(updates.isChecking || updates.isUpdating)
                    Button("Update Now") { Task { await updates.updateAll() } }
                        .disabled(!updates.updateAvailable || updates.isUpdating)
                }
                if let e = updates.errorMessage { Text(e).font(.caption).foregroundStyle(Color.juktoCoral) }
                Text("Updates are downloaded over HTTPS, checked against the publisher's SHA-256 and self-tested before use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Jukto", value: "v\(JuktoConstants.appVersion)")
                LabeledContent("Made by", value: JuktoConstants.author)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 800)
    }
}
