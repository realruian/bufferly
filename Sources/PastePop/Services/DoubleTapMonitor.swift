import AppKit

/// 检测「快速双击某个修饰键」（如双击 ⌥）来触发。
/// 依赖全局事件监听（需辅助功能 / 输入监控权限），未授权时回调不会触发。
///
/// 防误触：
/// - 按住不放不算（单次按压时长需小于阈值）。
/// - 与其它修饰键组合（如 ⌘⌥）不算（要求按下时只有目标修饰键）。
/// - 两次轻点之间若有任何普通按键 / 鼠标，序列作废。
@MainActor
final class DoubleTapMonitor {
    private let flag: NSEvent.ModifierFlags
    private let onTrigger: () -> Void

    private let maxTapDuration: TimeInterval = 0.35
    private let maxBetweenTaps: TimeInterval = 0.40

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var flagWasPressed = false
    private var downTimestamp: TimeInterval = 0
    private var lastTapTimestamp: TimeInterval = 0
    private var pendingCleanPress = false

    init(flag: NSEvent.ModifierFlags, onTrigger: @escaping () -> Void) {
        self.flag = flag
        self.onTrigger = onTrigger
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        flagWasPressed = false
        pendingCleanPress = false
        lastTapTimestamp = 0
    }

    private func handle(_ event: NSEvent) {
        // 普通按键 / 鼠标点击打断双击序列，避免组合操作误触发。
        guard event.type == .flagsChanged else {
            pendingCleanPress = false
            lastTapTimestamp = 0
            flagWasPressed = event.modifierFlags.contains(flag)
            return
        }

        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let current = event.modifierFlags.intersection(relevant)
        let isPressed = current.contains(flag)

        if isPressed, !flagWasPressed {
            // 按下边沿：必须是“干净”按下（只有目标修饰键）。
            pendingCleanPress = (current == flag)
            downTimestamp = event.timestamp
        } else if !isPressed, flagWasPressed {
            // 抬起边沿：判断是否构成一次有效轻点。
            let pressDuration = event.timestamp - downTimestamp

            if pendingCleanPress, pressDuration <= maxTapDuration {
                if lastTapTimestamp > 0, event.timestamp - lastTapTimestamp <= maxBetweenTaps {
                    lastTapTimestamp = 0
                    pendingCleanPress = false
                    flagWasPressed = isPressed
                    onTrigger()
                    return
                }
                lastTapTimestamp = event.timestamp
            } else {
                lastTapTimestamp = 0
            }

            pendingCleanPress = false
        }

        flagWasPressed = isPressed
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }
}
