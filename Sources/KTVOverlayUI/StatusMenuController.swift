import AppKit

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
    }

    private static let barTitle = "♪"

    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

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
        statusLine.title = actions.statusText()
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
        menu.addItem(.separator())
        menu.addItem(item("移動字幕（⌃⌥K）", #selector(toggleMoveMode)))
        menu.addItem(item("顯示或隱藏字幕", #selector(toggleVisibility)))
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
    @objc private func quit() { actions.quit() }
}
