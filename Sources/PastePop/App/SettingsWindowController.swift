import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: AppSettings = .shared) {
        let contentView = SettingsView(settings: settings)
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "PastePop 设置"
        window.minSize = NSSize(width: 680, height: 500)
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
    }

    func showSettings() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
