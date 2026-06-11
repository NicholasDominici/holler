import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var service: PingService!
    private var peers: [Peer] = []
    private let menu = NSMenu()

    private var wiredInUntil: Date?
    private var wiredInTimer: Timer?
    private var isWiredIn: Bool { wiredInUntil.map { $0 > Date() } ?? false }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        menu.delegate = self
        statusItem.menu = menu

        let storedName = UserDefaults.standard.string(forKey: Prefs.nameKey)
        service = PingService(displayName: storedName ?? defaultName())
        service.onPeersChanged = { [weak self] peers in
            self?.peers = peers
        }
        service.onPing = { from in
            let wasAudible = MediaController.shared.outputAudible
            NSSound(named: "Ping")?.play()
            PingHUD.shared.show(message: "\(from) is pinging you")
            if UserDefaults.standard.bool(forKey: Prefs.pauseMediaOnPing) {
                MediaController.shared.pause(wasAudible: wasAudible)
            }
        }
        service.start()

        if storedName == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.promptForName(initial: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    private func defaultName() -> String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? Host.current().localizedName ?? "Someone" : fullName
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbol = isWiredIn ? "headphones" : "hand.wave.fill"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Holler")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("You: \(service.displayName)"))
        if isWiredIn, let until = wiredInUntil {
            menu.addItem(disabledItem("🎧 Wired In until \(Self.timeFormatter.string(from: until))"))
        }
        menu.addItem(.separator())

        if peers.isEmpty {
            menu.addItem(disabledItem("No one else on this network"))
        } else {
            for peer in peers {
                let title = peer.isWiredIn ? "\(peer.name) — Wired In" : peer.name
                let item = NSMenuItem(title: title, action: #selector(pingPeer(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = peer
                let symbol = peer.isWiredIn ? "headphones" : "hand.wave"
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(wiredInMenuItem())

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let rename = NSMenuItem(title: "Change My Name…", action: #selector(changeName), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        if Bundle.main.bundleIdentifier != nil {
            let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Holler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func wiredInMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Wired In", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)
        let submenu = NSMenu()
        if isWiredIn {
            let end = NSMenuItem(title: "End Wired In", action: #selector(endWiredIn), keyEquivalent: "")
            end.target = self
            submenu.addItem(end)
            submenu.addItem(.separator())
        }
        for (title, minutes) in [("For 10 Minutes", 10), ("For 30 Minutes", 30), ("For 1 Hour", 60)] {
            let option = NSMenuItem(title: title, action: #selector(startWiredIn(_:)), keyEquivalent: "")
            option.target = self
            option.tag = minutes
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Wired In

    @objc private func startWiredIn(_ sender: NSMenuItem) {
        let until = Date().addingTimeInterval(TimeInterval(sender.tag * 60))
        wiredInUntil = until
        service.setWiredIn(until: until)
        wiredInTimer?.invalidate()
        wiredInTimer = Timer.scheduledTimer(
            withTimeInterval: until.timeIntervalSinceNow + 1,
            repeats: false
        ) { [weak self] _ in
            self?.endWiredIn()
        }
        updateStatusIcon()
    }

    @objc private func endWiredIn() {
        wiredInUntil = nil
        wiredInTimer?.invalidate()
        wiredInTimer = nil
        service.setWiredIn(until: nil)
        updateStatusIcon()
    }

    // MARK: - Actions

    @objc private func pingPeer(_ sender: NSMenuItem) {
        guard let peer = sender.representedObject as? Peer else { return }
        service.ping(peer) { [weak self] result in
            switch result {
            case .delivered:
                self?.flashStatus("✓")
            case .wiredIn:
                self?.flashStatus("🎧")
                PingHUD.shared.show(message: "\(peer.name) is Wired In", emoji: "🎧", duration: 3)
            case .failed:
                self?.flashStatus("✕")
                PingHUD.shared.show(message: "Couldn't reach \(peer.name)", emoji: "⚠️", duration: 3)
            }
        }
    }

    /// Briefly swaps the menu bar icon — the sender's subtle
    /// "it went through" confirmation.
    private func flashStatus(_ symbol: String) {
        guard let button = statusItem.button else { return }
        let originalImage = button.image
        button.image = nil
        button.title = symbol
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            button.title = ""
            if let self {
                self.updateStatusIcon()
            } else {
                button.image = originalImage
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func changeName() {
        promptForName(initial: false)
    }

    private func promptForName(initial: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = initial ? "Welcome to Holler" : "Change Your Name"
        alert.informativeText = "This is the name coworkers on this network will see when you ping them."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        field.stringValue = service.displayName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: Prefs.nameKey)
        service.update(displayName: name)
    }

    @objc private func toggleLoginItem() {
        let loginService = SMAppService.mainApp
        do {
            if loginService.status == .enabled {
                try loginService.unregister()
            } else {
                try loginService.register()
            }
        } catch {
            NSLog("Holler: failed to toggle login item: \(error)")
        }
    }
}
