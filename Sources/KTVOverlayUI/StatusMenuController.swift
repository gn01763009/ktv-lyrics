import AppKit
import KTVCore

/// The ♪ item in the menu bar and its menu. It holds no state of its own: every choice is handed to `Actions`.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    struct Actions {
        let statusText: () -> String
        let showEarlier: () -> Void
        let showLater: () -> Void
        let toggleMoveMode: () -> Void
        let toggleVisibility: () -> Void
        let quit: () -> Void
        let candidates: () async -> [LyricsCandidate]
        let selectedCandidateID: () -> String?
        let selectCandidate: (String) -> Void
        let importLRC: () -> Void
        let openSettings: () -> Void
    }

    private static let barTitle = "♪"

    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let versionsMenu = NSMenu()
    private var versionsRequest = 0

    init(actions: Actions, offsetStep: Double) {
        self.actions = actions
        super.init()
        statusItem.button?.title = Self.barTitle
        statusItem.menu = buildMenu(offsetStep: offsetStep)
    }

    func removeFromMenuBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === versionsMenu {
            loadVersions()
        } else {
            statusLine.title = actions.statusText()
        }
    }

    /// Fills the versions submenu when it opens. An answer that arrives after a newer open is dropped.
    private func loadVersions() {
        versionsRequest += 1
        let request = versionsRequest
        setVersionsMenu([placeholder("載入中…")])
        Task { [weak self, actions] in
            let found = await actions.candidates()
            guard let self, request == self.versionsRequest else { return }
            self.setVersionsMenu(self.versionItems(found, selected: actions.selectedCandidateID()))
        }
    }

    private func versionItems(_ found: [LyricsCandidate], selected: String?) -> [NSMenuItem] {
        guard !found.isEmpty else { return [placeholder("沒有其他版本")] }
        return found.map { candidate in
            let item = NSMenuItem(title: candidate.label, action: #selector(pickVersion(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.id
            item.state = candidate.id == selected ? .on : .off
            return item
        }
    }

    private func setVersionsMenu(_ items: [NSMenuItem]) {
        versionsMenu.removeAllItems()
        items.forEach(versionsMenu.addItem)
    }

    private func placeholder(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func buildMenu(offsetStep: Double) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        statusLine.title = actions.statusText()
        let step = String(format: "%.1f", offsetStep)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("字幕提早 \(step) 秒", #selector(showEarlier)))
        menu.addItem(item("字幕延後 \(step) 秒", #selector(showLater)))
        let versions = NSMenuItem(title: "換版本", action: nil, keyEquivalent: "")
        versionsMenu.delegate = self
        versions.submenu = versionsMenu
        menu.addItem(versions)
        menu.addItem(item("匯入 .lrc…", #selector(importLRC)))
        menu.addItem(.separator())
        menu.addItem(item("移動字幕（⌃⌥K）", #selector(toggleMoveMode)))
        menu.addItem(item("顯示或隱藏字幕", #selector(toggleVisibility)))
        menu.addItem(.separator())
        menu.addItem(item("設定…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("結束", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showEarlier() { actions.showEarlier() }
    @objc private func showLater() { actions.showLater() }
    @objc private func toggleMoveMode() { actions.toggleMoveMode() }
    @objc private func toggleVisibility() { actions.toggleVisibility() }
    @objc private func importLRC() { actions.importLRC() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func pickVersion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        actions.selectCandidate(id)
    }
    @objc private func quit() { actions.quit() }
}
