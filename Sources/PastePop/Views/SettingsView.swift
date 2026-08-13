import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var eventPostingPermission: EventPostingPermission

    @State private var selectedSection: SettingsSection = .general
    @State private var showExcludedApps = false
    @State private var showClearHistoryConfirmation = false
    @State private var storageSnapshot = ClipStorageSnapshot.current()

    init(
        settings: AppSettings,
        eventPostingPermission: EventPostingPermission = .shared
    ) {
        self.settings = settings
        self.eventPostingPermission = eventPostingPermission
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.title)
                    .font(.system(size: 28, weight: .bold))
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                ScrollView {
                    selectedSectionContent
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 740, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            eventPostingPermission.refresh()
            refreshStorageSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            eventPostingPermission.refresh()
            refreshStorageSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStorageDidChange)) { _ in
            refreshStorageSnapshot()
        }
        .sheet(isPresented: $showExcludedApps) {
            excludedAppsSheet
        }
        .confirmationDialog(
            "清空剪贴板历史？",
            isPresented: $showClearHistoryConfirmation
        ) {
            Button("清空未固定内容", role: .destructive) {
                requestClearHistory(keepPinned: true)
            }
            Button("全部清空", role: .destructive) {
                requestClearHistory(keepPinned: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: - 导航

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        HugeIconView(name: section.iconName, fallbackSystemName: section.fallbackSystemName)
                            .frame(width: 17, height: 17)

                        Text(section.title)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        selectedSection == section
                            ? Color.primary.opacity(0.08)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .general:
            generalSettings
        case .privacy:
            privacySettings
        case .history:
            historySettings
        }
    }

    // MARK: - 通用

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            settingsGroup("快捷键") {
                settingsRow("呼出 PastePop", caption: "在任意 App 中显示或隐藏面板") {
                    Picker("呼出 PastePop", selection: $settings.hotKeyPreset) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                if settings.hotKeyPreset.requiresInputMonitoring {
                    inlineNotice(
                        "\(settings.hotKeyPreset.displayName) 需要辅助功能权限",
                        actionTitle: "打开辅助功能设置",
                        action: eventPostingPermission.openPrivacySettings
                    )
                }

                if let error = settings.hotKeyRegistrationError {
                    inlineNotice(error)
                }
            }

            settingsGroup("粘贴") {
                settingsRow("按 Return 后") {
                    Picker("按 Return 后", selection: $settings.autoPasteAfterSelection) {
                        Text("复制到剪贴板").tag(false)
                        Text("粘贴到上一应用").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                settingsDivider

                settingsRow("复制或粘贴后关闭面板") {
                    Toggle("复制或粘贴后关闭面板", isOn: $settings.hideAfterPaste)
                        .labelsHidden()
                }

                if settings.autoPasteAfterSelection && !eventPostingPermission.isGranted {
                    inlineNotice(
                        "粘贴到上一应用需要辅助功能权限",
                        actionTitle: "授权",
                        action: requestPasteBackPermission
                    )
                }
            }

            settingsGroup("启动") {
                settingsRow("在 Dock 中显示应用") {
                    Toggle("在 Dock 中显示应用", isOn: $settings.showInDock)
                        .labelsHidden()
                }

                settingsDivider

                settingsRow("开机自动启动") {
                    Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - 隐私

    private var privacySettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            settingsGroup("内容保护") {
                settingsRow("敏感内容保护", caption: "密码、验证码和密钥不保存原文") {
                    Toggle("敏感内容保护", isOn: $settings.sensitiveFiltering)
                        .labelsHidden()
                }

                if settings.sensitiveFiltering {
                    settingsDivider

                    settingsRow("保留提示卡片") {
                        Toggle("保留提示卡片", isOn: $settings.storeSensitivePlaceholder)
                            .labelsHidden()
                    }
                }

                settingsDivider

                settingsRow("链接预览", caption: "开启后联网获取网页标题和图标") {
                    Toggle("链接预览", isOn: $settings.linkPreviewsEnabled)
                        .labelsHidden()
                }
            }

            settingsGroup("排除的 App") {
                settingsRow("不记录这些 App", caption: "已排除 \(settings.excludedBundleIDs.count) 个 App") {
                    Button("管理…") {
                        showExcludedApps = true
                    }
                }
            }
        }
    }

    // MARK: - 历史

    private var historySettings: some View {
        VStack(alignment: .leading, spacing: 28) {
            settingsGroup("保留规则") {
                settingsRow("保留时长") {
                    Picker("保留时长", selection: $settings.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.displayName).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }

                settingsDivider

                settingsRow("最大历史数量") {
                    Stepper(value: $settings.maxHistoryCount, in: 50...2_000, step: 50) {
                        Text("\(settings.maxHistoryCount)")
                            .monospacedDigit()
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .accessibilityLabel("最大历史数量")
                    .accessibilityValue("\(settings.maxHistoryCount) 条")
                }
            }

            settingsGroup("数据") {
                settingsRow("存储位置", caption: storageSnapshot.summary) {
                    Button("在 Finder 中显示") {
                        revealDatabaseInFinder()
                    }
                    .disabled(ClipStore.databasePath == nil)
                }

                settingsDivider

                settingsRow("清空历史") {
                    Button("清空…", role: .destructive) {
                        showClearHistoryConfirmation = true
                    }
                }
            }
        }
    }

    // MARK: - 通用组件

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Control: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 24)

            control()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 5)
    }

    private var settingsDivider: some View {
        Divider()
    }

    private func inlineNotice(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            HugeIconView(name: "alert-02", fallbackSystemName: "exclamationmark.triangle")
                .frame(width: 15, height: 15)
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 排除 App

    private var excludedAppsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("排除的 App")
                    .font(.title2.bold())

                Spacer()

                Button("完成") {
                    showExcludedApps = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            List {
                if settings.excludedBundleIDs.isEmpty {
                    Text("没有排除任何 App")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(appName(for: bundleID))
                            Spacer()
                            Button {
                                removeExcluded(bundleID)
                            } label: {
                                HugeIconView(name: "minus-sign-circle", fallbackSystemName: "minus.circle")
                                    .frame(width: 15, height: 15)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除 \(appName(for: bundleID))")
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("恢复建议") {
                    restoreRecommendedExcludedApps()
                }

                Spacer()

                Menu("添加 App") {
                    if addableApps.isEmpty {
                        Text("没有可添加的运行中 App")
                    } else {
                        ForEach(addableApps, id: \.bundleID) { app in
                            Button(app.name) {
                                addExcluded(app.bundleID)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 440, height: 440)
    }

    private struct RunningApp {
        let name: String
        let bundleID: String
    }

    private static let knownAppNames: [String: String] = [
        "com.apple.keychainaccess": "Keychain Access",
        "com.apple.Passwords": "Passwords",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass",
        "com.dashlane.dashlanephonefinal": "Dashlane",
        "com.nordpass.NordPass": "NordPass",
        "me.proton.pass": "Proton Pass",
        "com.roboform.mac": "RoboForm"
    ]

    private var addableApps: [RunningApp] {
        let selfBundleID = Bundle.main.bundleIdentifier
        var seen = Set(settings.excludedBundleIDs)

        return NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningApp? in
                guard
                    app.activationPolicy == .regular,
                    let bundleID = app.bundleIdentifier,
                    bundleID != selfBundleID,
                    let name = app.localizedName
                else {
                    return nil
                }

                guard seen.insert(bundleID).inserted else {
                    return nil
                }

                return RunningApp(name: name, bundleID: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appName(for bundleID: String) -> String {
        if
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: url),
            let name = bundle.localizedInfoDictionary?["CFBundleName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
        {
            return name
        }

        return Self.knownAppNames[bundleID] ?? bundleID
    }

    private func addExcluded(_ bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else {
            return
        }
        settings.excludedBundleIDs.append(bundleID)
    }

    private func removeExcluded(_ bundleID: String) {
        settings.excludedBundleIDs.removeAll { $0 == bundleID }
    }

    private func restoreRecommendedExcludedApps() {
        var bundleIDs = settings.excludedBundleIDs
        for bundleID in AppSettings.recommendedExcludedBundleIDs where !bundleIDs.contains(bundleID) {
            bundleIDs.append(bundleID)
        }
        settings.excludedBundleIDs = bundleIDs
    }

    private func requestClearHistory(keepPinned: Bool) {
        NotificationCenter.default.post(
            name: .clearHistoryRequested,
            object: nil,
            userInfo: ["keepPinned": keepPinned]
        )
    }

    private func requestPasteBackPermission() {
        let granted = eventPostingPermission.requestAccess()
        eventPostingPermission.refresh()

        if !granted && !eventPostingPermission.isGranted {
            eventPostingPermission.openPrivacySettings()
        }
    }

    private func revealDatabaseInFinder() {
        guard let path = ClipStore.databasePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func refreshStorageSnapshot() {
        storageSnapshot = ClipStorageSnapshot.current()
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case privacy
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .privacy: "隐私"
        case .history: "历史"
        }
    }

    var iconName: String {
        switch self {
        case .general: "information-circle"
        case .privacy: "square-lock-01"
        case .history: "file-empty-02"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .general: "gearshape"
        case .privacy: "lock"
        case .history: "clock"
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
