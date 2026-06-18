import AppKit

/// One entry in the "switch pet" submenu.
struct PetMenuEntry {
    let id: String
    let title: String
    let isActive: Bool
}

/// Owns the menu-bar `NSStatusItem` and routes each item to a host-supplied
/// action (technical design §5.4).
@MainActor
final class StatusItemController {
    struct Actions {
        var togglePetVisibility: () -> Void
        var switchPet: (String) -> Void
        var importNewPhoto: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let actions: Actions
    private let petsProvider: () -> [PetMenuEntry]

    init(actions: Actions, petsProvider: @escaping () -> [PetMenuEntry]) {
        self.actions = actions
        self.petsProvider = petsProvider
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "VibePet")
        }
        rebuild()
    }

    /// Rebuild the menu so the "switch pet" submenu reflects current assets.
    func rebuild() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "显示 / 隐藏宠物") { [weak self] in self?.actions.togglePetVisibility() })
        menu.addItem(switchPetItem())
        menu.addItem(ActionMenuItem(title: "导入新照片…") { [weak self] in self?.actions.importNewPhoto() })
        menu.addItem(ActionMenuItem(title: "打开设置…") { [weak self] in self?.actions.openSettings() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "退出 VibePet", key: "q") { [weak self] in self?.actions.quit() })
        statusItem.menu = menu
    }

    private func switchPetItem() -> NSMenuItem {
        let item = NSMenuItem(title: "切换宠物", action: nil, keyEquivalent: "")
        let entries = petsProvider()
        let submenu = NSMenu()
        if entries.isEmpty {
            let empty = NSMenuItem(title: "（还没有宠物）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for entry in entries {
                let petItem = ActionMenuItem(title: entry.title) { [weak self] in self?.actions.switchPet(entry.id) }
                petItem.state = entry.isActive ? .on : .off
                submenu.addItem(petItem)
            }
        }
        item.submenu = submenu
        return item
    }
}

/// `NSMenuItem` that invokes a stored closure, so callers don't need selectors.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
