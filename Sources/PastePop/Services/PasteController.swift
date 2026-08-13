import AppKit
import Carbon
import CoreGraphics

enum PasteController {
    @discardableResult
    @MainActor
    static func pasteIntoApplication(_ application: NSRunningApplication?) -> Bool {
        EventPostingPermission.shared.refresh()

        guard EventPostingPermission.shared.isGranted else {
            return false
        }

        guard let application else {
            return false
        }

        application.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCommandV()
        }

        return true
    }

    private static func sendCommandV() {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
