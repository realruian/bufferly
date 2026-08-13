import Foundation
import ServiceManagement

/// 开机自启，基于 SMAppService（macOS 13+）。仅对正式 .app 包有效，
/// `swift run` 的裸可执行文件登记会失败，此时静默忽略。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机自启状态，返回是否与目标一致。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            print("Failed to update login item: \(error)")
            return false
        }
    }
}
