import SwiftUI

/// Quick Panel 动效统一参数：高频键盘动作即时；鼠标微交互短促；弹性只用于 Pin 确认。
enum Motion {
    /// 强 ease-out：进入与系统反馈，起步快、收尾稳。
    private static func easeOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// 强 ease-in-out：屏幕内的位置移动 / 形变。
    private static func easeInOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    static let pressDown = easeOut(0.09)
    static let pressUp = easeOut(0.13)
    static let hoverIn = easeOut(0.10)
    static let hoverOut = easeOut(0.14)
    static let toastIn = easeOut(0.18)
    static let toastOut = easeOut(0.12)
    static let reducedFade = easeOut(0.10)
    static let onboarding = easeOut(0.22)
    static let listRemoval = easeOut(0.14)
    static let tabSlide = easeInOut(0.18)
    static let pinConfirmation = Animation.spring(duration: 0.22, bounce: 0.12)
}
