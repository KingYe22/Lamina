import AppKit
import LaminaCore

final class MenuBridge: NSObject, NSMenuDelegate {
    static let shared = MenuBridge()
    weak var workspace: Workspace?

    @objc func fire(_ sender: NSMenuItem) {
        guard let workspace, let action = sender.representedObject as? String else { return }
        workspace.perform(action)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let workspace, let path = sender.representedObject as? String else { return }
        workspace.open(url: URL(fileURLWithPath: path), place: false)
    }

    @objc func clearRecent(_ sender: NSMenuItem) {
        workspace?.perform("清除最近的文件")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "最近打开的文件" else { return }
        menu.removeAllItems()
        let recent = UserDefaults.standard.stringArray(forKey: Workspace.recentKey) ?? []
        if recent.isEmpty {
            let empty = NSMenuItem(title: "无最近文件", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for path in recent {
                let item = NSMenuItem(title: URL(fileURLWithPath: path).lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = path
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "清除最近的文件", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
}

private final class UsedKeyEquivalents {
    var tokens = Set<String>()
}

enum MenuBar {
    static func install(workspace: Workspace) {
        MenuBridge.shared.workspace = workspace
        let used = UsedKeyEquivalents()
        let main = NSMenu()
        main.addItem(top(MenuCatalog.appMenu, workspace: workspace, used: used))
        for menu in MenuCatalog.bar {
            main.addItem(top(menu, workspace: workspace, used: used))
        }
        NSApp.mainMenu = main
        refreshEnabled(workspace: workspace)
    }

    static func refreshEnabled(workspace: Workspace) {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items {
            refresh(item.submenu, workspace: workspace)
        }
    }

    private static func refresh(_ menu: NSMenu?, workspace: Workspace) {
        guard let menu else { return }
        for item in menu.items {
            if let action = item.representedObject as? String {
                if action == "还原" { item.isEnabled = workspace.active.model.canUndo }
                if action == "重做" { item.isEnabled = workspace.active.model.canRedo }
            }
            refresh(item.submenu, workspace: workspace)
        }
    }

    private static func top(_ node: MenuNode, workspace: Workspace, used: UsedKeyEquivalents) -> NSMenuItem {
        let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
        item.submenu = build(node, workspace: workspace, used: used)
        return item
    }

    private static func build(_ node: MenuNode, workspace: Workspace, used: UsedKeyEquivalents) -> NSMenu {
        let menu = NSMenu(title: node.title)
        if node.title == "最近打开的文件" {
            menu.delegate = MenuBridge.shared
        }
        for child in node.children {
            if child.isSeparator {
                menu.addItem(.separator())
                continue
            }
            if !child.children.isEmpty {
                let item = NSMenuItem(title: child.title, action: nil, keyEquivalent: "")
                item.submenu = build(child, workspace: workspace, used: used)
                menu.addItem(item)
                continue
            }
            let item = NSMenuItem(title: child.title, action: #selector(MenuBridge.fire(_:)), keyEquivalent: "")
            item.target = MenuBridge.shared
            item.representedObject = child.action
            if let chord = MenuCatalog.menuChord(for: child, keymap: workspace.active.model.keymap),
               let equivalent = ChordAppKit.menuEquivalent(chord) {
                let token = equivalent.0 + String(equivalent.1.rawValue)
                if used.tokens.insert(token).inserted {
                    item.keyEquivalent = equivalent.0
                    item.keyEquivalentModifierMask = equivalent.1
                }
            }
            menu.addItem(item)
        }
        return menu
    }
}
