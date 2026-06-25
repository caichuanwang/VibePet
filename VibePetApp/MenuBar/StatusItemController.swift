import AppKit
import VibePetCore

/// One entry in the "switch pet" submenu.
struct PetMenuEntry {
    let id: String
    let title: String
    let isActive: Bool
}

struct SessionMenuSummary: Equatable {
    let activeCount: Int
    let attentionCount: Int

    static func derive(from state: SessionState) -> SessionMenuSummary {
        SessionMenuSummary(activeCount: state.visibleSessions.count, attentionCount: state.attentionCount)
    }

    var title: String {
        "会话：\(activeCount) 个活跃，\(attentionCount) 个待处理"
    }
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
    private let sessionSummaryProvider: () -> SessionMenuSummary

    init(
        actions: Actions,
        petsProvider: @escaping () -> [PetMenuEntry],
        sessionSummaryProvider: @escaping () -> SessionMenuSummary = { SessionMenuSummary(activeCount: 0, attentionCount: 0) }
    ) {
        self.actions = actions
        self.petsProvider = petsProvider
        self.sessionSummaryProvider = sessionSummaryProvider
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "VibePet")
        }
        rebuild()
    }

    /// Rebuild the menu so the "switch pet" submenu reflects current assets.
    func rebuild() {
        let menu = NSMenu()
        let sessionSummary = NSMenuItem(title: sessionSummaryProvider().title, action: nil, keyEquivalent: "")
        sessionSummary.isEnabled = false
        menu.addItem(sessionSummary)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "显示 / 隐藏宠物") { [weak self] in self?.actions.togglePetVisibility() })
        menu.addItem(switchPetItem())
        menu.addItem(ActionMenuItem(title: "导入宠物…") { [weak self] in self?.actions.importNewPhoto() })
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
            let empty = NSMenuItem(title: "（还没有可用宠物）", action: nil, keyEquivalent: "")
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
