import AppKit

/// Borderless floating banner shown under the menu bar, e.g. "Hunter is pinging you".
/// No permissions needed, ignores clicks, fades out on its own.
final class PingHUD {
    static let shared = PingHUD()

    private var panels: [NSPanel] = []

    func show(message: String, emoji: String = "👋", duration: TimeInterval = 5) {
        let label = NSTextField(labelWithString: "\(emoji)  \(message)")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.sizeToFit()

        let hPadding: CGFloat = 18
        let vPadding: CGFloat = 12
        let size = NSSize(
            width: label.frame.width + hPadding * 2,
            height: label.frame.height + vPadding * 2
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: hPadding, y: vPadding))
        effect.addSubview(label)
        panel.contentView = effect

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let x = frame.maxX - size.width - 16
        let y = frame.maxY - size.height - 12 - CGFloat(panels.count) * (size.height + 10)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panels.append(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                self?.panels.removeAll { $0 === panel }
            })
        }
    }
}
