import Foundation

enum CapturePauseDuration: CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case untilResumed

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .fifteenMinutes:
            "15 分钟"
        case .oneHour:
            "1 小时"
        case .untilResumed:
            "直到手动恢复"
        }
    }

    func endDate(from now: Date = Date()) -> Date {
        switch self {
        case .fifteenMinutes:
            now.addingTimeInterval(15 * 60)
        case .oneHour:
            now.addingTimeInterval(60 * 60)
        case .untilResumed:
            .distantFuture
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var autoPasteAfterSelection: Bool {
        didSet {
            defaults.set(autoPasteAfterSelection, forKey: Keys.autoPasteAfterSelection)
        }
    }

    @Published var hideAfterPaste: Bool {
        didSet {
            defaults.set(hideAfterPaste, forKey: Keys.hideAfterPaste)
        }
    }

    @Published var maxHistoryCount: Int {
        didSet {
            let clampedValue = min(max(maxHistoryCount, 50), 2_000)
            if clampedValue != maxHistoryCount {
                maxHistoryCount = clampedValue
                return
            }

            defaults.set(maxHistoryCount, forKey: Keys.maxHistoryCount)
            NotificationCenter.default.post(name: .historyPolicyDidChange, object: nil)
        }
    }

    @Published var historyRetention: HistoryRetention {
        didSet {
            defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention)
            NotificationCenter.default.post(name: .historyPolicyDidChange, object: nil)
        }
    }

    /// 敏感内容过滤总开关（默认开，隐私优先）。
    @Published var sensitiveFiltering: Bool {
        didSet {
            defaults.set(sensitiveFiltering, forKey: Keys.sensitiveFiltering)
        }
    }

    /// 命中敏感内容时是否保留一个脱敏占位卡（关则直接丢弃，不入库）。
    @Published var storeSensitivePlaceholder: Bool {
        didSet {
            defaults.set(storeSensitivePlaceholder, forKey: Keys.storeSensitivePlaceholder)
        }
    }

    /// 链接预览：开启后会**联网**获取 URL 的标题与图标。默认关，守住本地优先 / 隐私优先。
    @Published var linkPreviewsEnabled: Bool {
        didSet {
            defaults.set(linkPreviewsEnabled, forKey: Keys.linkPreviewsEnabled)
        }
    }

    /// 暂停剪贴板记录的截止时间；`.distantFuture` 表示直到手动恢复。
    @Published private(set) var capturePauseUntil: Date? {
        didSet {
            if let capturePauseUntil {
                defaults.set(capturePauseUntil, forKey: Keys.capturePauseUntil)
            } else {
                defaults.removeObject(forKey: Keys.capturePauseUntil)
            }
        }
    }

    /// 用户创建的单层固定内容分组。条目归属保存在 clips 表中。
    @Published private(set) var pinGroups: [PinGroup] {
        didSet {
            if let data = try? JSONEncoder().encode(pinGroups) {
                defaults.set(data, forKey: Keys.pinGroups)
            }
        }
    }

    /// 是否已看过首次使用引导。
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// 开机自启（依赖 .app 包，由 LoginItem 实际登记）。
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LoginItem.setEnabled(launchAtLogin)
        }
    }

    /// 是否在 App 运行期间显示 Dock 图标；关闭时仍常驻菜单栏并继续监听剪贴板。
    @Published var showInDock: Bool {
        didSet {
            guard oldValue != showInDock else { return }
            defaults.set(showInDock, forKey: Keys.showInDock)
            NotificationCenter.default.post(name: .dockVisibilityDidChange, object: nil)
        }
    }

    /// 全局呼出快捷键预设。变更后发通知让 AppDelegate 重注册。
    @Published var hotKeyPreset: HotKeyPreset {
        didSet {
            guard oldValue != hotKeyPreset else { return }
            defaults.set(hotKeyPreset.rawValue, forKey: Keys.hotKeyPreset)
            NotificationCenter.default.post(name: .hotKeyPresetDidChange, object: nil)
        }
    }

    /// 排除采集的 App bundle identifier 列表。
    @Published var excludedBundleIDs: [String] {
        didSet {
            defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs)
        }
    }

    @Published private(set) var hotKeyRegistrationError: String?

    private let defaults: UserDefaults
    private var captureResumeTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.autoPasteAfterSelection) == nil {
            defaults.set(false, forKey: Keys.autoPasteAfterSelection)
        }

        if defaults.object(forKey: Keys.hideAfterPaste) == nil {
            defaults.set(true, forKey: Keys.hideAfterPaste)
        }

        if defaults.object(forKey: Keys.maxHistoryCount) == nil {
            defaults.set(500, forKey: Keys.maxHistoryCount)
        }

        if defaults.object(forKey: Keys.historyRetention) == nil {
            defaults.set(HistoryRetention.forever.rawValue, forKey: Keys.historyRetention)
        }

        if defaults.object(forKey: Keys.sensitiveFiltering) == nil {
            defaults.set(true, forKey: Keys.sensitiveFiltering)
        }

        if defaults.object(forKey: Keys.storeSensitivePlaceholder) == nil {
            defaults.set(true, forKey: Keys.storeSensitivePlaceholder)
        }

        if defaults.object(forKey: Keys.excludedBundleIDs) == nil {
            defaults.set(Self.defaultExcludedBundleIDs, forKey: Keys.excludedBundleIDs)
        }

        if defaults.object(forKey: Keys.showInDock) == nil {
            defaults.set(true, forKey: Keys.showInDock)
        }

        autoPasteAfterSelection = defaults.bool(forKey: Keys.autoPasteAfterSelection)
        hideAfterPaste = defaults.bool(forKey: Keys.hideAfterPaste)
        maxHistoryCount = defaults.integer(forKey: Keys.maxHistoryCount)
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: Keys.historyRetention) ?? "")
            ?? .forever
        sensitiveFiltering = defaults.bool(forKey: Keys.sensitiveFiltering)
        storeSensitivePlaceholder = defaults.bool(forKey: Keys.storeSensitivePlaceholder)
        // 默认 false（缺省即关）：联网获取链接预览是 opt-in。
        linkPreviewsEnabled = defaults.bool(forKey: Keys.linkPreviewsEnabled)
        let storedPauseUntil = defaults.object(forKey: Keys.capturePauseUntil) as? Date
        capturePauseUntil = storedPauseUntil.flatMap { $0 > Date() ? $0 : nil }
        if
            let data = defaults.data(forKey: Keys.pinGroups),
            let groups = try? JSONDecoder().decode([PinGroup].self, from: data)
        {
            pinGroups = groups
        } else {
            pinGroups = []
        }
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        // 以系统实际登记状态为准，避免偏好与系统不同步。
        launchAtLogin = LoginItem.isEnabled
        // 默认在 Dock 中显示，避免菜单栏图标不可见时失去可发现的启动入口。
        showInDock = defaults.bool(forKey: Keys.showInDock)
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Keys.hotKeyPreset) ?? "")
            ?? .optionSpace
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? Self.defaultExcludedBundleIDs

        if storedPauseUntil != nil, capturePauseUntil == nil {
            defaults.removeObject(forKey: Keys.capturePauseUntil)
        }
        scheduleCaptureResumeIfNeeded()
    }

    func setHotKeyRegistrationError(_ message: String?) {
        hotKeyRegistrationError = message
    }

    var isCapturePaused: Bool {
        guard let capturePauseUntil else { return false }
        return capturePauseUntil > Date()
    }

    var capturePauseSummary: String? {
        guard let capturePauseUntil, capturePauseUntil > Date() else { return nil }

        if capturePauseUntil.timeIntervalSinceNow > 50 * 365 * 24 * 60 * 60 {
            return "直到手动恢复"
        }

        return "至 \(capturePauseUntil.formatted(date: .omitted, time: .shortened))"
    }

    func pauseCapture(for duration: CapturePauseDuration, now: Date = Date()) {
        capturePauseUntil = duration.endDate(from: now)
        scheduleCaptureResumeIfNeeded()
    }

    func resumeCapture() {
        captureResumeTimer?.invalidate()
        captureResumeTimer = nil
        capturePauseUntil = nil
    }

    @discardableResult
    func createPinGroup(named rawName: String) -> PinGroup? {
        guard let name = normalizedPinGroupName(rawName) else { return nil }

        if let existing = pinGroups.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let group = PinGroup(name: name)
        pinGroups.append(group)
        return group
    }

    func renamePinGroup(id: UUID, to rawName: String) {
        guard
            let name = normalizedPinGroupName(rawName),
            !pinGroups.contains(where: {
                $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }),
            let index = pinGroups.firstIndex(where: { $0.id == id })
        else {
            return
        }

        pinGroups[index].name = name
    }

    func deletePinGroup(id: UUID) {
        pinGroups.removeAll { $0.id == id }
    }

    private func normalizedPinGroupName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    private func scheduleCaptureResumeIfNeeded() {
        captureResumeTimer?.invalidate()
        captureResumeTimer = nil

        guard let capturePauseUntil else { return }
        let interval = capturePauseUntil.timeIntervalSinceNow
        guard interval > 0 else {
            resumeCapture()
            return
        }

        // `.distantFuture` 代表手动恢复，不安排超长 Timer。
        guard interval < 50 * 365 * 24 * 60 * 60 else { return }

        captureResumeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeCapture()
            }
        }
    }

    static let recommendedExcludedBundleIDs = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.nordpass.NordPass",
        "me.proton.pass",
        "com.roboform.mac"
    ]

    private static let defaultExcludedBundleIDs = recommendedExcludedBundleIDs

    private enum Keys {
        static let autoPasteAfterSelection = "autoPasteAfterSelection"
        static let hideAfterPaste = "hideAfterPaste"
        static let maxHistoryCount = "maxHistoryCount"
        static let historyRetention = "historyRetention"
        static let sensitiveFiltering = "sensitiveFiltering"
        static let storeSensitivePlaceholder = "storeSensitivePlaceholder"
        static let linkPreviewsEnabled = "linkPreviewsEnabled"
        static let capturePauseUntil = "capturePauseUntil"
        static let pinGroups = "pinGroups"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let launchAtLogin = "launchAtLogin"
        static let showInDock = "showInDock"
        static let hotKeyPreset = "hotKeyPreset"
        static let excludedBundleIDs = "excludedBundleIDs"
    }
}
