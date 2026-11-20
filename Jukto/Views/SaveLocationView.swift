import SwiftUI

struct SaveLocationView: View {
    @EnvironmentObject var main: MainViewModel
    var body: some View {
        Button { main.chooseDirectory() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(main.saveDirectory.lastPathComponent).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PillButtonStyle())
        .help(main.saveDirectory.path)
    }
}
