import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let nameKey = "holler.displayName"

    private var statusItem: NSStatusItem!
    private var service: PingService!
    private var peers: [Peer] = []
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.wave.fill", accessibilityDescription: "Holler")
        }
        menu.delegate = self
        statusItem.menu = menu

        let storedName = UserDefaults.standard.string(forKey: Self.nameKey)
        service = PingService(displayName: storedName ?? defaultName())
        service.onPeersChanged = { [weak self] peers in
            self?.peers = peers
        }
        service.onPing = { from in
            NSSound(named: "Ping")?.play()
            PingHUD.shared.show(message: "\(from) is pinging you")
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

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("You: \(service.displayName)"))
        menu.addItem(.separator())

        if peers.isEmpty {
            menu.addItem(disabledItem("No one else on this network"))
        } else {
            for peer in peers {
                let item = NSMenuItem(title: peer.name, action: #selector(pingPeer(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = peer
                item.image = NSImage(systemSymbolName: "hand.wave", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
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

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func pingPeer(_ sender: NSMenuItem) {
        guard let peer = sender.representedObject as? Peer else { return }
        service.ping(peer) { [weak self] delivered in
            self?.flashStatus(delivered ? "✓" : "✕")
            if !delivered {
                PingHUD.shared.show(message: "Couldn't reach \(peer.name)", emoji: "⚠️", duration: 3)
            }
        }
    }

    /// Briefly swaps the menu bar icon for a checkmark — the sender's subtle
    /// "it went through" confirmation.
    private func flashStatus(_ symbol: String) {
        guard let button = statusItem.button else { return }
        let originalImage = button.image
        button.image = nil
        button.title = symbol
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            button.title = ""
            button.image = originalImage
        }
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
        UserDefaults.standard.set(name, forKey: Self.nameKey)
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
