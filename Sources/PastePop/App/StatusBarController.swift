import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    var onTogglePanel: (() -> Void)?
    var onShowSettings: (() -> Void)?

    private let statusItem: NSStatusItem
    private let togglePanelItem = NSMenuItem(title: "显示快速面板", action: #selector(togglePanel(_:)), keyEquivalent: "")
    private let pauseCaptureItem = NSMenuItem(title: "暂停记录", action: nil, keyEquivalent: "")
    private var pauseObservation: AnyCancellable?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        configureStatusItem()
        pauseObservation = AppSettings.shared.$capturePauseUntil.sink { [weak self] _ in
            self?.updatePauseMenu()
        }
    }

    func setPanelVisible(_ isVisible: Bool) {
        togglePanelItem.title = isVisible ? "隐藏快速面板" : "显示快速面板"
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = Self.makeStatusBarImage()
            button.toolTip = "PastePop"
        }

        let menu = NSMenu()

        togglePanelItem.target = self
        menu.addItem(togglePanelItem)

        menu.addItem(pauseCaptureItem)
        updatePauseMenu()

        menu.addItem(
            NSMenuItem(
                title: "设置...",
                action: #selector(showSettings(_:)),
                keyEquivalent: ","
            )
        )
        menu.items.last?.target = self

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 PastePop",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updatePauseMenu() {
        let settings = AppSettings.shared

        if settings.isCapturePaused {
            let summary = settings.capturePauseSummary.map { "（\($0)）" } ?? ""
            pauseCaptureItem.title = "继续记录\(summary)"
            pauseCaptureItem.action = #selector(resumeCapture(_:))
            pauseCaptureItem.target = self
            pauseCaptureItem.submenu = nil
            statusItem.button?.toolTip = "PastePop · 已暂停记录"
            return
        }

        pauseCaptureItem.title = "暂停记录"
        pauseCaptureItem.action = nil
        pauseCaptureItem.target = nil
        statusItem.button?.toolTip = "PastePop"

        let submenu = NSMenu()
        addPauseItem("15 分钟", action: #selector(pauseForFifteenMinutes(_:)), to: submenu)
        addPauseItem("1 小时", action: #selector(pauseForOneHour(_:)), to: submenu)
        addPauseItem("直到手动恢复", action: #selector(pauseUntilResumed(_:)), to: submenu)
        pauseCaptureItem.submenu = submenu
    }

    private func addPauseItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    /// 菜单栏图标：优先用 Resources 里的模板图（系统按浅/深色菜单栏自动着色），失败时回退 SF Symbol。
    private static func makeStatusBarImage() -> NSImage? {
        if
            let url = AppResources.url(forResource: "StatusBarIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PastePop")
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        onTogglePanel?()
    }

    @objc
    private func showSettings(_ sender: Any?) {
        onShowSettings?()
    }

    @objc
    private func pauseForFifteenMinutes(_ sender: Any?) {
        AppSettings.shared.pauseCapture(for: .fifteenMinutes)
    }

    @objc
    private func pauseForOneHour(_ sender: Any?) {
        AppSettings.shared.pauseCapture(for: .oneHour)
    }

    @objc
    private func pauseUntilResumed(_ sender: Any?) {
        AppSettings.shared.pauseCapture(for: .untilResumed)
    }

    @objc
    private func resumeCapture(_ sender: Any?) {
        AppSettings.shared.resumeCapture()
    }
}
