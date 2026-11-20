import SwiftUI

struct ContentView: View {
    @EnvironmentObject var main: MainViewModel
    @EnvironmentObject var downloads: DownloadViewModel
    @EnvironmentObject var auth: AuthCoordinator
    @EnvironmentObject var updates: UpdateService
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    UpdateBannerView()
                    URLInputView()

                    if let md = main.metadata {
                        VideoPreviewView(metadata: md)
                        FormatPickerView(options: $main.options, duration: md.duration, maxHeight: md.maxHeight,
                                         subtitleTracks: md.subtitleTracks, audioLanguages: md.audioLanguages)
                        if main.options.clipEnabled, let d = md.duration, d > 0 {
                            ClipRangeView(start: $main.options.clipStart, end: $main.options.clipEnd, duration: d)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                        DownloadSection()
                    } else if let err = main.errorMessage {
                        GlassCard(radius: JuktoConstants.smallRadius) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout).foregroundStyle(Color.juktoCoral)
                                    .textSelection(.enabled)
                                if main.canCapture, let u = main.lastURL {
                                    Button { main.captureRequest = CaptureRequest(url: u) } label: {
                                        Label("Find the video on the page…", systemImage: "scope")
                                    }
                                    .buttonStyle(PillButtonStyle(prominent: true))
                                }
                            }
                        }
                    }

                    DownloadListView()
                }
                .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 16)
                .animation(JuktoAnimation.pill, value: main.metadata)
                .animation(JuktoAnimation.pill, value: main.options.clipEnabled)
            }
            StatusBarView()
        }
        .frame(minWidth: JuktoZoom.minWidth, minHeight: JuktoZoom.minHeight)
        .background { TranslucentWindowBackground() }
        .sheet(item: $auth.request) { platform in
            LoginSheet(platform: platform)
        }
        .sheet(item: $main.captureRequest) { req in
            CaptureSheet(url: req.url, choosing: req.choosing,
                         onPick: { md in main.useSniffed(md) },
                         onPage: { u in main.urlText = u.absoluteString; main.analyze(userInitiated: true) })
        }
        .overlay {
            // A plain in-window overlay, not a sheet: no extra window is created, so it opens and closes instantly.
            if app.showDonation {
                DonationView {
                    app.showDonation = false
                    if app.quitRequested { app.quitConfirmed = true; NSApp.terminate(nil) } else { MainWindow.hide() }
                }
            }
        }
        .overlay { ToastOverlay() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
            Text("Jukto").font(.system(size: 22, weight: .semibold, design: .rounded))
            Spacer()
            DayNightToggle()
        }
    }
}
