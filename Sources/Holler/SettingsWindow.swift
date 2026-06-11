import AppKit

/// Small settings panel.
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show() {
        if window == nil { window = build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let header = NSTextField(labelWithString: "When someone pings you")
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        let pauseCheckbox = NSButton(
            checkboxWithTitle: "Pause playing media",
            target: self,
            action: #selector(togglePauseMedia(_:))
        )
        pauseCheckbox.state = UserDefaults.standard.bool(forKey: Prefs.pauseMediaOnPing) ? .on : .off

        let detail = NSTextField(wrappingLabelWithString:
            "Sends a system pause — like tapping ⏸ — so you can hear the person walking over."
        )
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = 300

        let stack = NSStackView(views: [header, pauseCheckbox, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(14, after: header)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Holler Settings"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.setContentSize(stack.fittingSize)
        return window
    }

    @objc private func togglePauseMedia(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Prefs.pauseMediaOnPing)
    }
}
