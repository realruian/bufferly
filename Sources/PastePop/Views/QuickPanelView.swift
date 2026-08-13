import AppKit
import SwiftUI

struct QuickPanelView: View {
    @StateObject private var viewModel: QuickPanelViewModel
    @ObservedObject private var appSettings: AppSettings
    @ObservedObject private var eventPostingPermission: EventPostingPermission
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool
    @State private var filterSuggestionsVisible = false
    @State private var selectedFilterSuggestionIndex = 0
    @State private var filterPalettePresented = false
    @State private var keyMonitor: Any?
    @State private var scrollWheelMonitor: Any?
    @State private var showPreview = false
    @State private var showOnboarding = false
    @State private var statusBanner: QuickPanelStatusMessage?
    @State private var statusDismissTask: Task<Void, Never>?
    @State private var editorTarget: EditorTarget?
    @State private var editorText = ""
    @State private var showEditor = false
    @State private var groupPendingDeletion: PinGroup?
    @State private var showGroupDeletionConfirmation = false
    /// 卡片墙滚动控制与几何信息（偏移 / 视口 / 内容宽），用于可见性判断和滚轮映射。
    @State private var wallPosition = ScrollPosition()
    @State private var wallGeometry = WallGeometry()

    init(
        viewModel: QuickPanelViewModel = QuickPanelViewModel(),
        appSettings: AppSettings = .shared,
        eventPostingPermission: EventPostingPermission = .shared
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.appSettings = appSettings
        self.eventPostingPermission = eventPostingPermission
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            cardWall
        }
        .frame(maxWidth: .infinity)
        .frame(height: QuickPanelView.panelHeight)
        // 外圆角 = 卡片圆角(14) + 卡片内边距(20)，与卡片同心。
        // 外层板子只使用低透明底色，前景卡片保持实底保证内容可读。
        .panelBackground(cornerRadius: 34)
        .overlay(alignment: .bottom) {
            if let statusBanner, !showPreview, !showOnboarding {
                QuickPanelStatusBannerView(banner: statusBanner)
                    .padding(.bottom, 18)
                    .transition(statusTransition)
            }
        }
        .overlay {
            if showPreview, let clip = viewModel.selectedClip {
                QuickPanelPreviewView(
                    clip: clip,
                    returnActionTitle: returnActionTitle,
                    onDismiss: { showPreview = false }
                )
                    .transition(.identity)
            }
        }
        .overlay {
            if showOnboarding {
                QuickPanelOnboardingView(
                    hotKeyPreset: appSettings.hotKeyPreset,
                    onDismiss: dismissOnboarding
                )
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? Motion.reducedFade : Motion.onboarding, value: showOnboarding)
        .onAppear {
            viewModel.startMonitoring()
            installKeyMonitor()
            installScrollWheelMonitor()
            focusSearch()
            showOnboarding = !AppSettings.shared.hasCompletedOnboarding
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let scrollWheelMonitor {
                NSEvent.removeMonitor(scrollWheelMonitor)
                self.scrollWheelMonitor = nil
            }
            statusDismissTask?.cancel()
            statusDismissTask = nil
        }
        .onChange(of: viewModel.query) {
            viewModel.handleQueryChange()
            selectedFilterSuggestionIndex = 0
            filterSuggestionsVisible = !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // 面板开始显示时只处理首帧需要的状态，避免权限和剪贴板读取与入场动画争抢主线程。
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelDidShow)) { _ in
            viewModel.prepareForPanelShow()
            showPreview = false
            filterPalettePresented = false
            filterSuggestionsVisible = false
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelDidFinishShowing)) { _ in
            eventPostingPermission.refresh()
            viewModel.captureLatestNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelDidRequestStatus)) { notification in
            handleStatusNotification(notification)
        }
        .alert(editorTitle, isPresented: $showEditor) {
            TextField(editorPlaceholder, text: $editorText)
            Button("取消", role: .cancel) {
                editorTarget = nil
            }
            Button("保存") {
                commitEditor()
            }
        }
        .confirmationDialog(
            "删除分组？",
            isPresented: $showGroupDeletionConfirmation,
            presenting: groupPendingDeletion
        ) { group in
            Button("删除“\(group.name)”", role: .destructive) {
                viewModel.deletePinGroup(id: group.id)
                groupPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                groupPendingDeletion = nil
            }
        } message: { _ in
            Text("分组中的固定内容会移到“未分组”，不会被删除。")
        }
    }

    // 364 = 顶栏(20+32) + 卡片墙(20+272+20)（DESIGN §4.1 建议高度）。
    static let panelHeight: CGFloat = 364

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            searchField

            Spacer(minLength: 8)

            if viewModel.board == .pinned {
                pinGroupMenu
            }

            PinboardTabs(selection: $viewModel.board)
        }
        // 四周统一 20：搜索上方到面板顶、左右边距、搜索行到卡片(由卡片墙 20 提供)全部一致。
        // 不再用固定高度，顶栏高度 = 20 顶部内边距 + 内容自然高度。
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    /// Paste 式 Power Search：筛选标签、输入框和筛选入口共用一颗玻璃药丸。
    private var searchField: some View {
        PowerSearchView(
            viewModel: viewModel,
            searchFocused: $searchFocused,
            suggestionsVisible: $filterSuggestionsVisible,
            selectedSuggestionIndex: $selectedFilterSuggestionIndex,
            filterPalettePresented: $filterPalettePresented,
            onSubmit: handleSearchSubmit
        )
    }

    private var pinGroupMenu: some View {
        Menu {
            groupOption("全部固定", selection: .all)
            groupOption("未分组", selection: .ungrouped)

            if !appSettings.pinGroups.isEmpty {
                Section("分组") {
                    ForEach(appSettings.pinGroups) { group in
                        groupOption(group.name, selection: .group(group.id))
                    }
                }
            }

            Divider()
            Button("新建分组…") {
                presentEditor(.newGroup(clipID: nil), text: "")
            }

            if
                case .group(let groupID) = viewModel.pinGroupSelection,
                let group = appSettings.pinGroups.first(where: { $0.id == groupID })
            {
                Button("重命名当前分组…") {
                    presentEditor(.renameGroup(group), text: group.name)
                }
                Button("删除当前分组…", role: .destructive) {
                    groupPendingDeletion = group
                    showGroupDeletionConfirmation = true
                }
            }
        } label: {
            pillLabel(viewModel.selectedPinGroupName)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("固定内容分组：\(viewModel.selectedPinGroupName)")
    }

    private func pillLabel(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if reduceTransparency {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Capsule())
    }

    private func groupOption(_ title: String, selection: PinGroupSelection) -> some View {
        Button {
            viewModel.selectPinGroup(selection)
        } label: {
            Text(viewModel.pinGroupSelection == selection ? "✓ \(title)" : title)
        }
    }

    private var returnActionTitle: String {
        guard appSettings.autoPasteAfterSelection, eventPostingPermission.isGranted else {
            return "只复制"
        }

        return "粘贴到上一应用"
    }

    // MARK: - Card wall

    private static let cardSpacing: CGFloat = 16
    private static let wallPadding: CGFloat = 20

    @ViewBuilder
    private var cardWall: some View {
        if viewModel.filteredClips.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.cardSpacing) {
                    ForEach(viewModel.filteredClips) { clip in
                        ClipCardView(
                            clip: clip,
                            searchQuery: viewModel.query,
                            onSelect: { viewModel.select(clipID: clip.id) },
                            onActivate: {
                                viewModel.select(clipID: clip.id)
                                activateSelection()
                            },
                            onTogglePin: { viewModel.togglePin(clipID: clip.id) }
                        )
                        .id(clip.id)
                        .contextMenu {
                            clipActions(for: clip)
                        }
                        // 只做退场（删除 / 取消固定）的轻微 fade + 缩小；入场保持直入，不做飞入。
                        .transition(
                            reduceMotion
                                ? .identity
                                : .asymmetric(
                                    insertion: .identity,
                                    removal: .opacity.combined(with: .scale(scale: 0.98))
                                )
                        )
                    }
                }
                .padding(.horizontal, Self.wallPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            // Tahoe 滚动边缘柔化：左右边缘的卡片淡入面板圆角，不硬裁切。
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
            .scrollPosition($wallPosition)
            .onScrollGeometryChange(for: WallGeometry.self) { geometry in
                WallGeometry(
                    offsetX: geometry.contentOffset.x,
                    viewportWidth: geometry.containerSize.width,
                    contentWidth: geometry.contentSize.width
                )
            } action: { _, geometry in
                wallGeometry = geometry
            }
            .onChange(of: viewModel.scrollRequest) {
                guard let request = viewModel.scrollRequest else { return }
                handleScrollRequest(request)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - 卡片墙滚动

    private func handleScrollRequest(_ request: QuickPanelViewModel.ScrollRequest) {
        switch request.kind {
        case .resetToFront:
            // 程序性复位（呼出 / 搜索 / 新条目）：直接就位，不播开场滚动。
            wallPosition.scrollTo(edge: .leading)
        case .reveal(let clipID):
            revealCard(clipID)
        }
    }

    /// 键盘导航是高频动作：目标卡不可见时即时定位，不叠加脉冲或滚动动画。
    private func revealCard(_ clipID: ClipItem.ID) {
        guard
            let index = viewModel.filteredClips.firstIndex(where: { $0.id == clipID }),
            wallGeometry.viewportWidth > 0
        else {
            return
        }

        let cardStride = ClipCardView.width + Self.cardSpacing
        let cardMinX = Self.wallPadding + CGFloat(index) * cardStride
        let cardMaxX = cardMinX + ClipCardView.width
        let visibleMinX = wallGeometry.offsetX
        let visibleMaxX = wallGeometry.offsetX + wallGeometry.viewportWidth

        if cardMinX >= visibleMinX, cardMaxX <= visibleMaxX {
            return
        }

        let maxOffset = max(0, wallGeometry.contentWidth - wallGeometry.viewportWidth)
        let rawTarget = cardMinX < visibleMinX
            ? cardMinX - Self.wallPadding
            : cardMaxX + Self.wallPadding - wallGeometry.viewportWidth
        let targetX = min(max(0, rawTarget), maxOffset)

        wallPosition.scrollTo(x: targetX)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            HugeIconView(
                name: viewModel.board == .pinned ? "pin" : "copy-01",
                fallbackSystemName: viewModel.board == .pinned ? "pin" : "doc.on.clipboard"
            )
            .frame(width: 30, height: 30)
            .foregroundStyle(.tertiary)

            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !viewModel.query.isEmpty {
            return "没有匹配内容"
        }

        if viewModel.filter.isActive {
            return "没有符合筛选的内容"
        }

        return viewModel.board == .pinned ? "还没有固定的内容" : "复制的文字、图片、文件会出现在这里"
    }

    // MARK: - Actions

    /// 卡片右键动作列表，保持为高频操作，不放开发者转换类动作。
    @ViewBuilder
    private func clipActions(for clip: ClipItem) -> some View {
        Button(returnActionTitle) {
            viewModel.select(clipID: clip.id, revealFocus: false)
            activateSelection()
        }
        .disabled(clip.isSensitive)

        Button("复制") {
            viewModel.select(clipID: clip.id, revealFocus: false)
            copyOnlyAndClose()
        }
        .disabled(clip.isSensitive)

        Button(clip.isPinned ? "取消固定" : "固定") {
            viewModel.togglePin(clipID: clip.id)
        }

        if clip.isPinned {
            Button("重命名…") {
                presentEditor(.renameClip(clip.id), text: clip.customName ?? "")
            }

            Menu("移动到分组") {
                Button(clip.pinGroupID == nil ? "✓ 未分组" : "未分组") {
                    viewModel.movePinnedClip(clipID: clip.id, to: nil)
                }

                ForEach(appSettings.pinGroups) { group in
                    Button(clip.pinGroupID == group.id ? "✓ \(group.name)" : group.name) {
                        viewModel.movePinnedClip(clipID: clip.id, to: group.id)
                    }
                }

                Divider()
                Button("新建分组…") {
                    presentEditor(.newGroup(clipID: clip.id), text: "")
                }
            }
        }

        Divider()
        Button("删除", role: .destructive) {
            withAnimation(reduceMotion ? Motion.reducedFade : Motion.listRemoval) {
                viewModel.delete(clipID: clip.id)
            }
        }
    }

    private var editorTitle: String {
        switch editorTarget {
        case .renameClip:
            "命名固定内容"
        case .newGroup:
            "新建分组"
        case .renameGroup:
            "重命名分组"
        case nil:
            "编辑"
        }
    }

    private var editorPlaceholder: String {
        switch editorTarget {
        case .renameClip:
            "例如：公司地址"
        case .newGroup, .renameGroup:
            "分组名称"
        case nil:
            "名称"
        }
    }

    private func presentEditor(_ target: EditorTarget, text: String) {
        editorTarget = target
        editorText = text
        showEditor = true
    }

    private func commitEditor() {
        guard let editorTarget else { return }

        switch editorTarget {
        case .renameClip(let clipID):
            viewModel.renamePinnedClip(clipID: clipID, to: editorText)
        case .newGroup(let clipID):
            if let group = viewModel.createPinGroup(named: editorText), let clipID {
                viewModel.movePinnedClip(clipID: clipID, to: group.id)
            }
        case .renameGroup(let group):
            viewModel.renamePinGroup(id: group.id, to: editorText)
        }

        self.editorTarget = nil
        focusSearch()
    }

    // MARK: - 覆盖层

    private var statusTransition: AnyTransition {
        .modifier(
            active: StatusTransitionModifier(opacity: 0, offsetY: reduceMotion ? 0 : 8),
            identity: StatusTransitionModifier(opacity: 1, offsetY: 0)
        )
    }

    private func handleStatusNotification(_ notification: Notification) {
        guard let message = notification.userInfo?[QuickPanelStatusPayload.messageKey] as? String else {
            return
        }

        let kindRawValue = notification.userInfo?[QuickPanelStatusPayload.kindKey] as? String
        let kind = kindRawValue.flatMap(QuickPanelStatusKind.init(rawValue:)) ?? .info
        showStatus(message, kind: kind)
    }

    private func showStatus(_ message: String, kind: QuickPanelStatusKind) {
        statusDismissTask?.cancel()
        withAnimation(reduceMotion ? Motion.reducedFade : Motion.toastIn) {
            statusBanner = QuickPanelStatusMessage(message: message, kind: kind)
        }
        statusDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? Motion.reducedFade : Motion.toastOut) {
                statusBanner = nil
            }
        }
    }

    // MARK: - 键盘

    /// 让搜索框聚焦。无边框面板里若没有任何 first responder，方向键 / Return 都不会进响应链。
    private func focusSearch() {
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    /// 安装本地 scrollWheel 监听：把「纵向为主」的滚轮 / 触控板滚动映射为卡片墙横向滚动
    /// （Paste 惯例，Magic Mouse / 滚轮鼠标才能逛卡片墙）；横向手势保持原生行为。
    private func installScrollWheelMonitor() {
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScrollWheel(event)
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        // 只接管浮动无边框面板自己的滚动；预览 / 引导覆盖层期间放行（预览里有纵向滚动区）。
        guard
            let window = event.window,
            window.styleMask.contains(.borderless),
            window.level == .floating,
            !showPreview, !showOnboarding,
            !viewModel.filteredClips.isEmpty
        else {
            return event
        }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        guard abs(deltaY) > abs(deltaX) else {
            return event
        }

        // 非精确滚动（传统滚轮）按行计数，放大到舒适的步进。
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 24
        let maxOffset = max(0, wallGeometry.contentWidth - wallGeometry.viewportWidth)
        let targetX = min(max(0, wallGeometry.offsetX - deltaY * factor), maxOffset)
        wallPosition.scrollTo(x: targetX)
        return nil
    }

    /// 安装本地 keyDown 监听，集中接管面板内的导航 / 动作键。
    ///
    /// 为什么不用 `onMoveCommand` / `keyboardShortcut`：无边框浮层面板里 SwiftUI 的
    /// 方向键命令依赖被聚焦视图的响应链，焦点在搜索框上时方向键又会被字段当作移动光标，
    /// 二者必有一失。本地监听在面板为 key 时直接拿到 keyDown，最可靠且不挑焦点。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // 只接管浮动无边框面板自己的按键，避免干扰设置窗口等其它窗口。
        guard
            let window = event.window,
            window.styleMask.contains(.borderless),
            window.level == .floating
        else {
            return event
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // 引导覆盖层期间：Return / Esc / 空格关闭引导；直接打字则关掉引导并把
        // 按键透传给搜索框（第一反应就是搜索的用户不该被卡住）；其余组合键吞掉。
        if showOnboarding {
            switch (event.keyCode, mods) {
            case (36, []), (76, []), (53, []), (49, []):
                dismissOnboarding()
                return nil
            default:
                if
                    mods.subtracting(.shift).isEmpty,
                    let character = event.charactersIgnoringModifiers?.first,
                    character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
                {
                    dismissOnboarding()
                    return event
                }
                return nil
            }
        }

        if mods == [.command], event.keyCode == 3 { // ⌘F：聚焦搜索；已聚焦时打开全部筛选
            if searchFocused {
                filterSuggestionsVisible = false
                filterPalettePresented = true
            } else {
                focusSearch()
            }
            return nil
        }

        if filterSuggestionsVisible, !viewModel.filterSuggestions.isEmpty {
            switch (event.keyCode, mods) {
            case (125, []): // ↓
                selectedFilterSuggestionIndex = min(
                    selectedFilterSuggestionIndex + 1,
                    viewModel.filterSuggestions.count - 1
                )
                return nil
            case (126, []): // ↑
                selectedFilterSuggestionIndex = max(selectedFilterSuggestionIndex - 1, 0)
                return nil
            case (36, []), (76, []): // Return
                applySelectedFilterSuggestion()
                return nil
            case (53, []): // Esc
                filterSuggestionsVisible = false
                return nil
            default:
                break
            }
        }

        if event.keyCode == 51, mods.isEmpty, viewModel.query.isEmpty, viewModel.filter.isActive {
            viewModel.removeLastFilterToken()
            return nil
        }

        // 搜索框里已有文字时，左右方向键应交给原生文本编辑（移动光标 / 配合 Shift 选择）。
        if
            searchFocused,
            !viewModel.query.isEmpty,
            mods.isEmpty,
            event.keyCode == 123 || event.keyCode == 124
        {
            return event
        }

        switch (event.keyCode, mods) {
        case (123, []), (126, []): // ← / ↑
            viewModel.selectPrevious()
            return nil
        case (124, []), (125, []): // → / ↓
            viewModel.selectNext()
            return nil
        case (36, []), (76, []): // Return / 小键盘 Enter
            activateSelection()
            return nil
        case (36, [.command]), (76, [.command]): // ⌘Return 纯文本粘贴
            activateSelection(mode: .plainText)
            return nil
        case (36, [.option]), (76, [.option]): // ⌥Return 仅复制后关闭
            copyOnlyAndClose()
            return nil
        case (51, [.command]): // ⌘⌫ 删除选中
            viewModel.deleteSelected()
            return nil
        case (35, [.command]): // ⌘P 固定 / 取消固定
            viewModel.togglePinSelected()
            return nil
        case (18, [.command]): // ⌘1 剪贴板分区
            switchBoard(.clipboard)
            return nil
        case (19, [.command]): // ⌘2 已固定分区
            switchBoard(.pinned)
            return nil
        case (49, []): // 空格：搜索为空时切换 Quick Look 预览，否则放行给搜索框打空格
            if viewModel.query.isEmpty {
                showPreview.toggle()
                return nil
            }
            return event
        case (53, []): // Esc：筛选浮层→预览→搜索/筛选→面板
            if filterPalettePresented {
                filterPalettePresented = false
                return nil
            }
            if showPreview {
                showPreview = false
                return nil
            }
            if !viewModel.query.isEmpty || viewModel.filter.isActive {
                viewModel.clearSearchAndFilters()
                return nil
            }
            NotificationCenter.default.post(name: .quickPanelDidRequestClose, object: nil)
            return nil
        default:
            // 其余按键（打字、退格、其它组合）放行给搜索框 / 系统。
            return event
        }
    }

    private func dismissOnboarding() {
        showOnboarding = false
        AppSettings.shared.hasCompletedOnboarding = true
    }

    /// 键盘切换分区（⌘1/⌘2），与点击分段标签共用同一滑动动效。
    private func switchBoard(_ board: QuickPanelViewModel.Board) {
        guard viewModel.board != board else { return }
        viewModel.board = board
    }

    private func activateSelection(mode: QuickPanelViewModel.PasteMode = .original) {
        if viewModel.pasteSelected(mode: mode) {
            NotificationCenter.default.post(name: .quickPanelDidRequestPaste, object: nil)
        } else {
            showStatus(pasteFailureMessage, kind: .warning)
        }
    }

    private func handleSearchSubmit() {
        if filterSuggestionsVisible, !viewModel.filterSuggestions.isEmpty {
            applySelectedFilterSuggestion()
        } else {
            activateSelection()
        }
    }

    private func applySelectedFilterSuggestion() {
        let suggestions = viewModel.filterSuggestions
        guard !suggestions.isEmpty else { return }
        let index = min(max(0, selectedFilterSuggestionIndex), suggestions.count - 1)
        viewModel.applyFilterToken(suggestions[index])
        viewModel.query = ""
        filterSuggestionsVisible = false
        selectedFilterSuggestionIndex = 0
        focusSearch()
    }

    /// 仅复制到剪贴板、不自动粘贴，然后关闭面板。
    private func copyOnlyAndClose() {
        if viewModel.pasteSelected() {
            NotificationCenter.default.post(name: .quickPanelDidRequestClose, object: nil)
        } else {
            showStatus(pasteFailureMessage, kind: .warning)
        }
    }

    private var pasteFailureMessage: String {
        guard let selectedClip = viewModel.selectedClip else {
            return "没有可复制内容"
        }

        if selectedClip.isSensitive {
            return "没有保存原文，请回到原来的 App 重新复制"
        }

        return "无法写入剪贴板"
    }
}

private enum EditorTarget {
    case renameClip(ClipItem.ID)
    case newGroup(clipID: ClipItem.ID?)
    case renameGroup(PinGroup)
}

/// 卡片墙滚动几何：内容偏移 + 视口宽 + 内容总宽。
private struct WallGeometry: Equatable {
    var offsetX: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var contentWidth: CGFloat = 0
}

private struct StatusTransitionModifier: ViewModifier {
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

#Preview {
    QuickPanelView()
        .frame(width: 980, height: QuickPanelView.panelHeight)
}
