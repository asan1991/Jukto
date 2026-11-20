import SwiftUI

/// Popover content: paste URL → analyze → configure → download.
struct MenuBarView: View {
    @EnvironmentObject var downloads: DownloadViewModel
    @StateObject private var vm = MainViewModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
                Text("Jukto").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button { MainWindow.show() } label: { Image(systemName: "macwindow") }
                    .buttonStyle(IconButtonStyle()).help("Open Jukto")
            }

            if let md = vm.metadata { configure(md) } else { input }

            let live = downloads.items.filter { !$0.status.isFinished }.prefix(3)
            if !live.isEmpty {
                VStack(spacing: 8) { ForEach(Array(live)) { MiniRow(item: $0) } }
            }
        }
        .padding(14)
        .frame(width: 350)
        .animation(JuktoAnimation.pill, value: vm.metadata)
        .onAppear {
            if vm.urlText.isEmpty, vm.metadata == nil,
               let s = NSPasteboard.general.string(forType: .string), let u = URLDetector.firstURL(in: s) {
                vm.urlText = u.absoluteString
            }
        }
    }

    private var input: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Paste a video link", text: $vm.urlText).textFieldStyle(.plain).onSubmit { analyze() }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))

            HStack {
                Button { vm.paste(analyze: true) } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(PillButtonStyle())
                Spacer()
                Button { analyze() } label: {
                    if vm.isAnalyzing { ProgressView().controlSize(.small).frame(width: 52) } else { Text("Analyze") }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(vm.urlText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isAnalyzing)
            }
            if let e = vm.errorMessage {
                Text(e).font(.caption).foregroundStyle(Color.juktoCoral).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A link with no particular video in it opens the page in the main window so a video can be chosen there.
    @MainActor private func analyze() {
        let text = vm.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLDetector.firstURL(in: text), !URLDetector.pointsToVideo(url) {
            let main = AppState.shared.main
            main.urlText = url.absoluteString
            main.analyze(userInitiated: true)
            MainWindow.show()
            return
        }
        vm.analyze()
    }

    private func configure(_ md: VideoMetadata) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ThumbnailView(url: md.thumbnail, width: 88)
                VStack(alignment: .leading, spacing: 4) {
                    PlatformBadge(platform: md.platform)
                    Text(md.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    if let d = md.duration { Text(d.timecode).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            FormatPickerView(options: $vm.options, duration: md.duration, maxHeight: md.maxHeight,
                             subtitleTracks: md.subtitleTracks, audioLanguages: md.audioLanguages,
                             showClip: false, compact: true)
            HStack {
                Button("Back") { vm.reset() }.buttonStyle(PillButtonStyle())
                Spacer()
                Button {
                    downloads.enqueue(md, options: vm.options, directory: vm.saveDirectory)
                    vm.reset()
                } label: { Label("Download", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct MiniRow: View {
    @ObservedObject var item: DownloadItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.metadata.title).font(.caption).lineLimit(1)
                Spacer()
                Text(item.status == .queued ? "Queued" : String(format: "%.0f%%", item.progress * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GlassProgressBar(value: item.progress, tint: item.status == .compressing ? .juktoLavender : .accentColor, height: 4)
        }
    }
}
