import SwiftUI

/// A pill that opens a menu (language lists etc.).
struct MenuPill<Content: View>: View {
    let title: String
    var isSelected: Bool
    let content: Content

    init(title: String, isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.title = title; self.isSelected = isSelected; self.content = content()
    }

    var body: some View {
        Menu { content } label: {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(Capsule(style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct FormatPickerView: View {
    @Binding var options: DownloadOptions
    var duration: Double? = nil
    var maxHeight: Int? = nil
    var subtitleTracks: [SubtitleTrack] = []
    var audioLanguages: [String] = []
    var showClip = true
    var compact = false

    var body: some View {
        GlassCard(padding: compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                row("Format") {
                    ForEach(OutputFormat.allCases) { f in
                        ChoicePill(title: f.label, isSelected: options.format == f) { options.format = f }
                    }
                }
                if !options.format.isAudio {
                    row("Resolution") {
                        ForEach(Resolution.allCases) { r in
                            ChoicePill(title: r.label, isSelected: options.resolution == r,
                                       isDimmed: r != .best && (maxHeight.map { r.rawValue > $0 } ?? false)) { options.resolution = r }
                        }
                    }
                }
                if showClip, let d = duration, d > 0 {
                    row("Trim") {
                        ChoicePill(title: "Trim", symbol: "scissors", isSelected: options.clipEnabled) {
                            options.clipEnabled.toggle()
                            if options.clipEnabled, options.clipEnd <= options.clipStart { options.clipEnd = d }
                        }
                    }
                }
                if audioLanguages.count > 1 { row("Audio") { audioControls } }
                if !options.format.isAudio, !subtitleTracks.isEmpty { row("Subtitles") { subtitleControls } }
                row("Cover art") { coverControls }
                row("Target size") { sizeControls }
            }
        }
        .animation(JuktoAnimation.pill, value: options)
        .onChange(of: options.format) { _, new in
            if new == .mov, options.subtitleMode == .embed { options.subtitleMode = .srt }   // .mov can't hold embedded subs reliably
            if new == .webm, options.coverMode == .embed { options.coverMode = .file }       // .webm can't hold cover art
        }
    }

    // MARK: audio
    @ViewBuilder private var audioControls: some View {
        ChoicePill(title: "Default", isSelected: options.audioTrack == nil) { options.audioTrack = nil }
        MenuPill(title: audioTitle, isSelected: options.audioTrack != nil && options.audioTrack != "*") {
            ForEach(audioLanguages, id: \.self) { code in
                Button(languageName(code)) { options.audioTrack = code }
            }
        }
        if !options.format.isAudio {
            ChoicePill(title: "All tracks", isSelected: options.audioTrack == "*") { options.audioTrack = "*" }
        }
    }
    private var audioTitle: String {
        if let a = options.audioTrack, a != "*" { return languageName(a) }
        return "Language"
    }

    // MARK: subtitles
    @ViewBuilder private var subtitleControls: some View {
        ChoicePill(title: "Off", isSelected: options.subtitleMode == .off) { options.subtitleMode = .off }
        if options.format != .mov {
            ChoicePill(title: "Embed", isSelected: options.subtitleMode == .embed) { setSubtitles(.embed) }
        }
        ChoicePill(title: ".srt file", isSelected: options.subtitleMode == .srt) { setSubtitles(.srt) }
        ChoicePill(title: ".vtt file", isSelected: options.subtitleMode == .vtt) { setSubtitles(.vtt) }
        if options.subtitleMode != .off {
            MenuPill(title: subtitleTitle, isSelected: true) {
                ForEach(subtitleTracks) { t in
                    Button(t.name) { options.subtitleCode = t.code; options.subtitleIsAuto = t.isAuto }
                }
            }
        }
    }
    private func setSubtitles(_ mode: SubtitleMode) {
        options.subtitleMode = mode
        if options.subtitleCode == nil, let t = defaultTrack {
            options.subtitleCode = t.code; options.subtitleIsAuto = t.isAuto
        }
    }
    private var defaultTrack: SubtitleTrack? {
        let sys = Locale.current.language.languageCode?.identifier
        return subtitleTracks.first { !$0.isAuto && $0.code.hasPrefix(sys ?? "\u{0}") }
            ?? subtitleTracks.first { !$0.isAuto } ?? subtitleTracks.first
    }
    private var subtitleTitle: String {
        subtitleTracks.first { $0.code == options.subtitleCode && $0.isAuto == options.subtitleIsAuto }?.name ?? "Choose language"
    }
    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    // MARK: cover art
    @ViewBuilder private var coverControls: some View {
        ChoicePill(title: "Off", isSelected: options.coverMode == .off) { options.coverMode = .off }
        ChoicePill(title: "File (.jpg)", isSelected: options.coverMode == .file) { options.coverMode = .file }
        if options.format != .webm {
            ChoicePill(title: "Embed", isSelected: options.coverMode == .embed) { options.coverMode = .embed }
        }
    }

    // MARK: size
    @ViewBuilder private var sizeControls: some View {
        ChoicePill(title: "Original", isSelected: options.targetSizeMB == nil) { options.targetSizeMB = nil }
        ChoicePill(title: "Custom", isSelected: options.targetSizeMB != nil) {
            if options.targetSizeMB == nil { options.targetSizeMB = 25 }
        }
        if options.targetSizeMB != nil {
            HStack(spacing: 4) {
                TextField("MB", value: Binding(get: { options.targetSizeMB ?? 25 },
                                               set: { options.targetSizeMB = max(1, $0) }),
                          format: .number)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 44)
                Text("MB").foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        }
    }

    @ViewBuilder
    private func row<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        let pills = ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }.padding(.vertical, 1)
        }
        if compact {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                pills
            }
        } else {
            HStack(spacing: 10) {
                Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                pills
            }
        }
    }
}
