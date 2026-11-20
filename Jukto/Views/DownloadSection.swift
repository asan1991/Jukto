import SwiftUI

struct DownloadSection: View {
    @EnvironmentObject var main: MainViewModel
    @EnvironmentObject var downloads: DownloadViewModel

    var body: some View {
        HStack(spacing: 10) {
            SaveLocationView()
            Spacer(minLength: 0)
            Button {
                guard let md = main.metadata else { return }
                downloads.enqueue(md, options: main.options, directory: main.saveDirectory)
                main.reset()
            } label: {
                Label(main.options.clipEnabled ? "Download Trimmed" : "Download", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(main.metadata == nil)
        }
    }
}
