import SwiftUI
import AppKit

/// Interface size: ⌘+ / ⌘− / ⌘0 and Settings. The whole interface is drawn at this scale (like page zoom in a
/// browser, text included) and the window grows or shrinks with it. The window itself is free-form: drag any edge or
/// corner, snap it to a screen edge, or use the Window menu.
enum JuktoZoom {
    static let minScale = 0.8, maxScale = 2.0, step = 0.1
    static let minWidth: CGFloat = 460, minHeight: CGFloat = 420

    static func clamp(_ v: Double) -> Double { v <= 0 ? 1 : min(max(v, minScale), maxScale) }
    static var scale: Double { clamp(UserDefaults.standard.double(forKey: JuktoConstants.Keys.textScale)) }

    @MainActor static func set(_ value: Double) {
        let old = scale
        let new = clamp((value * 10).rounded() / 10)
        guard abs(new - old) > 0.001 else { return }
        UserDefaults.standard.set(new, forKey: JuktoConstants.Keys.textScale)
        resizeWindow(ratio: new / old)
    }
    @MainActor static func zoomIn() { set(scale + step) }
    @MainActor static func zoomOut() { set(scale - step) }
    @MainActor static func reset() { set(1) }

    @MainActor private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == JuktoConstants.mainWindowIdentifier }
    }

    /// Keeps the layout the same at a new scale: the window changes size by the same ratio (top-left corner stays put).
    @MainActor private static func resizeWindow(ratio: Double) {
        guard let w = mainWindow, !w.styleMask.contains(.fullScreen) else { return }
        var f = w.frame
        let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? f
        let nw = min(f.width * ratio, vis.width), nh = min(f.height * ratio, vis.height)
        f.origin.y += f.height - nh
        f.size = NSSize(width: nw, height: nh)
        if f.maxX > vis.maxX { f.origin.x = max(vis.minX, vis.maxX - f.width) }
        if f.minY < vis.minY { f.origin.y = vis.minY }
        w.setFrame(f, display: true, animate: true)
    }

    enum Snap { case left, right, fill, center }
    @MainActor static func snap(_ s: Snap) {
        guard let w = mainWindow, let vis = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = vis
        switch s {
        case .left: f.size.width = vis.width / 2
        case .right: f.size.width = vis.width / 2; f.origin.x = vis.midX
        case .fill: break
        case .center:
            f.size = NSSize(width: vis.width * 0.6, height: vis.height * 0.8)
            f.origin = NSPoint(x: vis.midX - f.width / 2, y: vis.midY - f.height / 2)
        }
        w.setFrame(f, display: true, animate: true)
    }
}

struct ZoomContainer<Content: View>: View {
    @AppStorage(JuktoConstants.Keys.textScale) private var stored = 1.0
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let s = JuktoZoom.clamp(stored)
        GeometryReader { geo in
            content
                .frame(width: geo.size.width / s, height: geo.size.height / s)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(minWidth: JuktoZoom.minWidth * s, minHeight: JuktoZoom.minHeight * s)
    }
}
