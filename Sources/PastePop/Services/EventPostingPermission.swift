import AppKit
import ApplicationServices

@MainActor
final class EventPostingPermission: ObservableObject {
    static let shared = EventPostingPermission()

    @Published private(set) var isGranted: Bool

    init() {
        isGranted = Self.preflight()
    }

    func refresh() {
        isGranted = Self.preflight()
    }

    @discardableResult
    func requestAccess() -> Bool {
        // “复制后粘贴到上一应用”通过 CGEvent 模拟 ⌘V。用户实际在系统设置里授予的是
        // 辅助功能权限，所以 UI 状态应以 AX 信任为准；CoreGraphics 的
        // PostEvent preflight 在部分系统上不会跟辅助功能列表同步，导致误报未授权。
        isGranted = Self.accessibilityTrusted(prompt: true)
        return isGranted
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func preflight() -> Bool {
        accessibilityTrusted(prompt: false)
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}
