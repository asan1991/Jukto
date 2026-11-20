import AppKit
import SwiftUI
import Combine

/// Circular progress arc drawn over the status item icon.
final class ProgressArcView: NSView {
    private let arc = CAShapeLayer()
    var progress: Double? {
        didSet {
            isHidden = progress == nil
            CATransaction.begin(); CATransaction.setAnimationDuration(0.2)
            arc.strokeEnd = CGFloat(max(0.02, min(1, progress ?? 0)))
            CATransaction.commit()
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; isHidden = true
        arc.fillColor = nil; arc.lineWidth = 2; arc.lineCap = .round
        arc.strokeColor = NSColor.controlAccentColor.cgColor; arc.strokeEnd = 0
        layer?.addSublayer(arc)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // let clicks reach the button
    override func layout() {
        super.layout()
        arc.frame = bounds
        let r = min(bounds.width, bounds.height) / 2 - 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: r,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        arc.path = path
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let arc = ProgressArcView(frame: .zero)
    private var bag = Set<AnyCancellable>()
    private var state: AppState?

    func install(state: AppState) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let b = item.button {
            let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Jukto")
            img?.isTemplate = true
            b.image = img
            b.target = self; b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            arc.frame = b.bounds; arc.autoresizingMask = [.width, .height]
            b.addSubview(arc)
        }
        self.state = state          // the popover's SwiftUI content is built on first click, not at launch
        popover.behavior = .transient
        popover.animates = true

        state.downloads.$overallProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.arc.progress = $0 }
            .store(in: &bag)
    }

    /// Download finished: swap in a check mark and pulse the icon for ~2 seconds.
    func celebrate() {
        guard let b = statusItem?.button else { return }
        let original = b.image
        let done = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Download complete")
        done?.isTemplate = true
        b.image = done
        func pulse(_ remaining: Int) {
            guard remaining > 0 else { b.alphaValue = 1; return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2; b.animator().alphaValue = 0.25
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2; b.animator().alphaValue = 1
                }, completionHandler: { pulse(remaining - 1) })
            })
        }
        pulse(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { b.image = original }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Jukto", action: #selector(openMain), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Jukto", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            if popover.contentViewController == nil, let state {
                let host = NSHostingController(rootView: MenuBarView().environmentObject(state.downloads))
                host.sizingOptions = .preferredContentSize
                popover.contentViewController = host
            }
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    @objc private func openMain() { popover.performClose(nil); MainWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
