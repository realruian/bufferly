import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var doubleTapMonitor: DoubleTapMonitor?
    private let onHotKeyPressed: () -> Void

    init(onHotKeyPressed: @escaping () -> Void) {
        self.onHotKeyPressed = onHotKeyPressed
    }

    /// 按预设注册全局快捷键，可重复调用以切换。组合键走 Carbon，双击修饰键走事件监听。
    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()

        switch preset.activation {
        case let .combo(keyCode, carbonModifiers):
            return registerCombo(keyCode: keyCode, carbonModifiers: carbonModifiers)
        case let .doubleTapModifier(flag):
            let monitor = DoubleTapMonitor(flag: flag) { [weak self] in
                self?.onHotKeyPressed()
            }
            monitor.start()
            doubleTapMonitor = monitor
            return true
        }
    }

    private func registerCombo(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard
                    let event,
                    let userData
                else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == 1 else {
                    return status
                }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    manager.onHotKeyPressed()
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            return false
        }

        let hotKeyID = EventHotKeyID(
            signature: fourCharacterCode("BFLY"),
            id: 1
        )

        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return false
        }

        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        doubleTapMonitor?.stop()
        doubleTapMonitor = nil
    }

    deinit {
        MainActor.assumeIsolated {
            unregister()
        }
    }

    private func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
