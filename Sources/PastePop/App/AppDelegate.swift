import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickPanelWindowController: QuickPanelWindowController?
    private let quickPanelViewModel = QuickPanelViewModel()
    private var settingsWindowController: SettingsWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusBarController: StatusBarController?
    private var pasteTargetApplication: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例守卫：若已存在相同 bundle id 的另一个进程，直接退出自己。
        // 防止「登录项里登记了多份 .app 路径」时开机出现多个 UI 实例。
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let hasOtherInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != myPID }
        if hasOtherInstance {
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureNotifications()

        // 后台只保留监听与数据模型；面板窗口按需创建，关闭后即可释放卡片视图和缩略图。
        quickPanelViewModel.startMonitoring()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.toggleQuickPanel(animated: true)
        }
        registerHotKey(AppSettings.shared.hotKeyPreset)

        let statusBarController = StatusBarController()
        statusBarController.onTogglePanel = { [weak self] in
            self?.toggleQuickPanel(animated: true)
        }
        statusBarController.onShowSettings = { [weak self] in
            self?.showSettings(nil)
        }
        self.statusBarController = statusBarController

        if !AppSettings.shared.hasCompletedOnboarding {
            ensureQuickPanelController().showPanel(animated: true)
        }
        updateStatusBarPanelState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings(nil)
        return true
    }

    private func toggleQuickPanel(animated: Bool) {
        if let controller = quickPanelWindowController, controller.isPanelVisible {
            controller.hidePanel(animated: animated)
        } else {
            updatePasteTargetApplication()
            ensureQuickPanelController().showPanel(animated: animated)
        }

        updateStatusBarPanelState()
    }

    private func ensureQuickPanelController() -> QuickPanelWindowController {
        if let quickPanelWindowController {
            return quickPanelWindowController
        }

        let controller = QuickPanelWindowController(viewModel: quickPanelViewModel)
        controller.onVisibilityChange = { [weak self] _ in
            self?.updateStatusBarPanelState()
        }
        controller.onDidHide = { [weak self, weak controller] in
            guard let self, self.quickPanelWindowController === controller else { return }
            self.quickPanelWindowController = nil
        }
        quickPanelWindowController = controller
        return controller
    }

    private func handlePasteRequest() {
        let settings = AppSettings.shared
        var statusMessage: String?
        var statusKind: QuickPanelStatusKind = .success

        if settings.autoPasteAfterSelection {
            if !PasteController.pasteIntoApplication(pasteTargetApplication) {
                statusMessage = autoPasteFailureMessage()
                statusKind = .warning
            }
        } else {
            statusMessage = "已复制到剪贴板"
        }

        // 失败提示不能被「完成后关闭面板」吞掉：保持面板可见并说明原因，
        // 否则用户以为已粘贴，实际什么都没发生。
        if let statusMessage, statusKind == .warning {
            postStatus(statusMessage, kind: statusKind)
            return
        }

        if settings.hideAfterPaste {
            hidePanelAfterPasteIfNeeded()
        } else if let statusMessage {
            postStatus(statusMessage, kind: statusKind)
        }
    }

    private func autoPasteFailureMessage() -> String {
        EventPostingPermission.shared.refresh()

        if !EventPostingPermission.shared.isGranted {
            return "已复制，粘贴到上一应用需要授权"
        }

        if pasteTargetApplication == nil {
            return "已复制，未找到上一应用"
        }

        return "已复制，粘贴到上一应用失败"
    }

    private func postStatus(_ message: String, kind: QuickPanelStatusKind) {
        NotificationCenter.default.post(
            name: .quickPanelDidRequestStatus,
            object: nil,
            userInfo: [
                QuickPanelStatusPayload.messageKey: message,
                QuickPanelStatusPayload.kindKey: kind.rawValue
            ]
        )
    }

    private func hidePanelAfterPasteIfNeeded() {
        if AppSettings.shared.hideAfterPaste {
            quickPanelWindowController?.hidePanel(animated: true)
            updateStatusBarPanelState()
        }
    }

    private func updatePasteTargetApplication() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        guard frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        pasteTargetApplication = frontmostApplication
    }

    private func updateStatusBarPanelState() {
        statusBarController?.setPanelVisible(quickPanelWindowController?.isPanelVisible == true)
    }

    private func configureNotifications() {
        NotificationCenter.default.addObserver(
            forName: .quickPanelDidRequestPaste,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePasteRequest()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .quickPanelDidRequestClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.quickPanelWindowController?.hidePanel(animated: true)
                self?.updateStatusBarPanelState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hotKeyPresetDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKey(AppSettings.shared.hotKeyPreset)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .dockVisibilityDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
            }
        }
    }

    private func registerHotKey(_ preset: HotKeyPreset) {
        let didRegister = hotKeyManager?.register(preset) == true
        let errorMessage = didRegister ? nil : "\(preset.displayName) 注册失败，可能已被其它 App 占用。"
        AppSettings.shared.setHotKeyRegistrationError(errorMessage)

        if let errorMessage {
            postStatus(errorMessage, kind: .warning)
        }
    }

    private func configureMenu() {
        NSApp.mainMenu = Self.makeMainMenu()
    }

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            NSMenuItem(
                title: "设置...",
                action: #selector(showSettings(_:)),
                keyEquivalent: ","
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "退出 PastePop",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")

        editMenu.addItem(
            NSMenuItem(
                title: "撤销",
                action: NSSelectorFromString("undo:"),
                keyEquivalent: "z"
            )
        )

        let redoItem = NSMenuItem(
            title: "重做",
            action: NSSelectorFromString("redo:"),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())

        editMenu.addItem(
            NSMenuItem(
                title: "剪切",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
        )
        editMenu.addItem(
            NSMenuItem(
                title: "复制",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
        )
        editMenu.addItem(
            NSMenuItem(
                title: "粘贴",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(
                title: "全选",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        return mainMenu
    }

    @objc
    private func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }

        settingsWindowController?.showSettings()
    }
}
