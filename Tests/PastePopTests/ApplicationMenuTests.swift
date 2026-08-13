import AppKit
import Testing
@testable import PastePop

@Suite("ApplicationMenu")
@MainActor
struct ApplicationMenuTests {
    @Test("标准文字编辑快捷键注册到主菜单")
    func standardTextEditingCommands() throws {
        let mainMenu = AppDelegate.makeMainMenu()
        let editMenu = try #require(mainMenu.items.last?.submenu)

        #expect(editMenu.title == "编辑")
        expectShortcut("z", action: NSSelectorFromString("undo:"), in: editMenu)
        expectShortcut("z", modifiers: [.command, .shift], action: NSSelectorFromString("redo:"), in: editMenu)
        expectShortcut("x", action: #selector(NSText.cut(_:)), in: editMenu)
        expectShortcut("c", action: #selector(NSText.copy(_:)), in: editMenu)
        expectShortcut("v", action: #selector(NSText.paste(_:)), in: editMenu)
        expectShortcut("a", action: #selector(NSText.selectAll(_:)), in: editMenu)
    }

    private func expectShortcut(
        _ key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        action: Selector,
        in menu: NSMenu
    ) {
        let item = menu.items.first { $0.action == action }
        #expect(item?.keyEquivalent == key)
        #expect(item?.keyEquivalentModifierMask == modifiers)
    }
}
