import SwiftUI
import AppKit

/// The red close button shows the thank-you window first; closing THAT window hides (not destroys) the main window.
final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    static let shared = WindowCloseInterceptor()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            if UserDefaults.standard.bool(forKey: JuktoConstants.Keys.showThanksOnClose) {
                AppState.shared.showDonation = true
            } else {
                sender.orderOut(nil)
            }
        }
        return false
    }
}

/// Tags the window, makes it translucent (95% alpha in both themes) and installs the close interceptor.
/// Plain alpha only — no NSVisualEffectView / blur, which is what costs GPU time.
struct TranslucentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowTaggingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowTaggingView: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); configure() }

    private func configure() {
        guard let w = window else { return }
        w.identifier = NSUserInterfaceItemIdentifier(JuktoConstants.mainWindowIdentifier)
        w.delegate = WindowCloseInterceptor.shared
        w.isOpaque = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        // Free-form window, like Finder: any size, any edge or corner, snapping to screen edges, full screen.
        w.styleMask.formUnion([.resizable, .miniaturizable, .closable])
        w.collectionBehavior.formUnion([.fullScreenPrimary, .managed])

        var color = NSColor.windowBackgroundColor
        w.effectiveAppearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.windowBackgroundColor
            color = resolved.withAlphaComponent(JuktoConstants.darkWindowAlpha)   // same translucency in light and dark
        }
        w.backgroundColor = color
    }
}
