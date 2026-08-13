import Foundation

extension Notification.Name {
    static let quickPanelDidRequestPaste = Notification.Name("quickPanelDidRequestPaste")
    static let quickPanelDidRequestClose = Notification.Name("quickPanelDidRequestClose")
    static let quickPanelDidRequestStatus = Notification.Name("quickPanelDidRequestStatus")
    /// 面板每次显示后广播，驱动 SwiftUI 重新聚焦搜索框。
    static let quickPanelDidShow = Notification.Name("quickPanelDidShow")
    /// 面板入场完成后广播，用于执行不影响首帧的权限和剪贴板刷新。
    static let quickPanelDidFinishShowing = Notification.Name("quickPanelDidFinishShowing")
    static let hotKeyPresetDidChange = Notification.Name("hotKeyPresetDidChange")
    static let dockVisibilityDidChange = Notification.Name("dockVisibilityDidChange")
    static let clearHistoryRequested = Notification.Name("clearHistoryRequested")
    static let historyPolicyDidChange = Notification.Name("historyPolicyDidChange")
}

enum QuickPanelStatusKind: String {
    case info
    case success
    case warning
}

enum QuickPanelStatusPayload {
    static let messageKey = "message"
    static let kindKey = "kind"
}
