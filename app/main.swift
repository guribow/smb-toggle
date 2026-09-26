// SMBToggle: メニューバーから SMB 共有をマウントする / 取り外すアプリ
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var busy: Set<String> = []   // マウント処理中の共有名

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        // Finder など他の手段でマウント・取り外しされてもアイコンを更新
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func volumesChanged() { updateIcon() }

    private func updateIcon() {
        let anyMounted = SMBCore.all().contains(where: \.mounted)
        let symbol = anyMounted ? "externaldrive.fill.badge.wifi" : "externaldrive.badge.wifi"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SMBToggle")
            ?? NSImage(systemSymbolName: anyMounted ? "network" : "network.slash", accessibilityDescription: "SMBToggle")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // メニューを開くたびに作り直す
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let about = NSMenuItem(title: "SMBToggle について", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let list = SMBCore.all()
        if list.isEmpty {
            menu.addItem(disabledItem("登録した共有なし"))
        }
        for s in list {
            var title = s.registered ? s.name : "\(s.name)（未登録）"
            if busy.contains(s.name) { title += " …接続中" }
            let item = NSMenuItem(title: title, action: #selector(toggleShare(_:)), keyEquivalent: "")
            item.target = self
            item.state = s.mounted ? .on : .off
            item.representedObject = s.name
            item.toolTip = s.mounted ? "クリックで取り外す（\(s.mountPoint!)）" : "クリックでマウントする（\(s.url ?? "")）"
            item.isEnabled = !busy.contains(s.name)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let mountAll = NSMenuItem(title: "すべてマウント", action: #selector(mountAll), keyEquivalent: "")
        mountAll.target = self
        mountAll.isEnabled = list.contains { $0.registered && !$0.mounted }
        menu.addItem(mountAll)
        let unmountAll = NSMenuItem(title: "すべて取り外す", action: #selector(unmountAll), keyEquivalent: "")
        unmountAll.target = self
        unmountAll.isEnabled = list.contains(where: \.mounted)
        menu.addItem(unmountAll)

        menu.addItem(.separator())
        let add = NSMenuItem(title: "共有を追加…", action: #selector(addShare), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let unregistered = list.filter { !$0.registered }
        if !unregistered.isEmpty {
            let reg = NSMenuItem(title: "マウント中の共有を登録", action: #selector(registerMounted), keyEquivalent: "")
            reg.target = self
            menu.addItem(reg)
        }
        let shares = SMBCore.loadShares()
        if !shares.isEmpty {
            let removeItem = NSMenuItem(title: "登録から外す", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for s in shares {
                let i = NSMenuItem(title: "\(s.name)  \(s.url)", action: #selector(removeShare(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = s.url
                sub.addItem(i)
            }
            removeItem.submenu = sub
            menu.addItem(removeItem)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleShare(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let s = SMBCore.all().first(where: { $0.name == name }) else { return }
        if s.mounted {
            do { try SMBCore.unmount(s) } catch { showError(error) }
            updateIcon()
        } else {
            mountInBackground([s])
        }
    }

    // マウントはサーバーの応答やログイン画面を待つので、メインスレッドを止めない
    private func mountInBackground(_ targets: [ShareStatus]) {
        let targets = targets.filter { !busy.contains($0.name) }
        targets.forEach { busy.insert($0.name) }
        for s in targets {
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: Error?
                do { try SMBCore.mount(s) } catch { failure = error }
                DispatchQueue.main.async {
                    self.busy.remove(s.name)
                    self.updateIcon()
                    if let failure { self.showError(failure) }
                }
            }
        }
    }

    @objc private func mountAll() {
        mountInBackground(SMBCore.all().filter { $0.registered && !$0.mounted })
    }

    @objc private func unmountAll() {
        var errors: [String] = []
        for s in SMBCore.all() where s.mounted {
            do { try SMBCore.unmount(s) } catch { errors.append(error.localizedDescription) }
        }
        updateIcon()
        if !errors.isEmpty { showError(SMBError(errors.joined(separator: "\n\n"))) }
    }

    @objc private func addShare() {
        let alert = NSAlert()
        alert.messageText = "SMB 共有を追加"
        alert.informativeText = "例：smb://nas.local/share または smb://user@192.168.1.10/share\n表示名は空欄なら共有名になります。"
        let url = NSTextField(frame: NSRect(x: 0, y: 30, width: 320, height: 24))
        url.placeholderString = "smb://ホスト/共有名"
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        name.placeholderString = "表示名（省略可）"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 54))
        box.addSubview(url)
        box.addSubview(name)
        alert.accessoryView = box
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = url
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let n = name.stringValue.trimmingCharacters(in: .whitespaces)
        do { _ = try SMBCore.add(url: url.stringValue, name: n.isEmpty ? nil : n) } catch { showError(error) }
    }

    // マウント中で未登録の共有を登録する（Finder の「サーバへ接続」でつないだものなど）
    @objc private func registerMounted() {
        var errors: [String] = []
        for s in SMBCore.all() where !s.registered {
            guard let from = s.mountFrom else { continue }
            do { _ = try SMBCore.add(url: "smb:" + from) } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { showError(SMBError(errors.joined(separator: "\n"))) }
    }

    @objc private func removeShare(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String,
              let s = SMBCore.loadShares().first(where: { $0.url == url }) else { return }
        do { try SMBCore.remove(s) } catch { showError(error) }
        updateIcon()
    }

    /// macOS 標準の「このアプリについて」（アイコン・名前・バージョン・著作権は Info.plist から）
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.version: ""])   // ビルド番号の「(…)」は出さない
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "SMBToggle"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
