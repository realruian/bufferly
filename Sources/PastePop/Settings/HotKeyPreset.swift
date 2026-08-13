import AppKit
import Carbon

/// 快捷键激活方式：组合键（Carbon 注册）或双击修饰键（事件监听）。
enum HotKeyActivation {
    case combo(keyCode: UInt32, carbonModifiers: UInt32)
    case doubleTapModifier(NSEvent.ModifierFlags)
}

/// 全局呼出快捷键预设。用预设而非任意录制，兼顾「可配置」与实现成本。
enum HotKeyPreset: String, CaseIterable, Identifiable {
    // 组合键（无需权限）
    case optionSpace
    case controlSpace
    case commandShiftSpace
    case commandShiftV
    case commandOptionV
    // 双击修饰键（需辅助功能/输入监控权限）
    case doubleOption
    case doubleCommand
    case doubleControl
    case doubleShift

    var id: String { rawValue }

    var activation: HotKeyActivation {
        switch self {
        case .optionSpace:
            .combo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
        case .controlSpace:
            .combo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey))
        case .commandShiftSpace:
            .combo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .commandShiftV:
            .combo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .commandOptionV:
            .combo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | optionKey))
        case .doubleOption:
            .doubleTapModifier(.option)
        case .doubleCommand:
            .doubleTapModifier(.command)
        case .doubleControl:
            .doubleTapModifier(.control)
        case .doubleShift:
            .doubleTapModifier(.shift)
        }
    }

    /// 是否为双击修饰键（依赖事件监听权限）。
    var requiresInputMonitoring: Bool {
        if case .doubleTapModifier = activation {
            return true
        }
        return false
    }

    /// 紧凑符号形式，如 `⌥ Space`，用于面板内宽度受限的提示。
    var symbols: String {
        switch self {
        case .optionSpace:
            "⌥ Space"
        case .controlSpace:
            "⌃ Space"
        case .commandShiftSpace:
            "⌘⇧ Space"
        case .commandShiftV:
            "⌘⇧V"
        case .commandOptionV:
            "⌘⌥V"
        case .doubleOption:
            "双击 ⌥"
        case .doubleCommand:
            "双击 ⌘"
        case .doubleControl:
            "双击 ⌃"
        case .doubleShift:
            "双击 ⇧"
        }
    }

    /// 完整显示文案：符号 + 口语化按键名，照顾不认识修饰键符号的用户。
    var displayName: String {
        switch self {
        case .optionSpace:
            "⌥ Space（Option + 空格）"
        case .controlSpace:
            "⌃ Space（Control + 空格）"
        case .commandShiftSpace:
            "⌘⇧ Space（Command + Shift + 空格）"
        case .commandShiftV:
            "⌘⇧V（Command + Shift + V）"
        case .commandOptionV:
            "⌘⌥V（Command + Option + V）"
        case .doubleOption:
            "连按两下 ⌥ Option"
        case .doubleCommand:
            "连按两下 ⌘ Command"
        case .doubleControl:
            "连按两下 ⌃ Control"
        case .doubleShift:
            "连按两下 ⇧ Shift"
        }
    }
}
