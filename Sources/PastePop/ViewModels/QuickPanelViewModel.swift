import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class QuickPanelViewModel: ObservableObject {
    /// Pinboard 分段：剪贴板（全部历史）/ 已固定。
    enum Board: String, CaseIterable, Identifiable {
        case clipboard = "剪贴板"
        case pinned = "已固定"

        var id: String { rawValue }

        var dotColor: Color {
            switch self {
            case .clipboard:
                .secondary
            case .pinned:
                .orange
            }
        }
    }

    typealias PasteMode = ClipboardWriter.Mode

    /// 卡片墙滚动请求。`token` 保证相同目标的连续请求也能触发 onChange。
    struct ScrollRequest: Equatable {
        enum Kind: Equatable {
            /// 程序性复位（呼出 / 搜索变化 / 新条目）：直接回到最前，不播动画。
            case resetToFront
            /// 键盘导航：目标卡不完全可见时才滚入视野，带动画和瞬时脉冲。
            case reveal(ClipItem.ID)
        }

        let kind: Kind
        private let token = UUID()
    }

    private struct FilterCacheKey: Equatable {
        let clipsRevision: Int
        let board: Board
        let pinGroupSelection: PinGroupSelection
        let query: String
        let filter: ClipFilter
        let timeBucket: Int
    }

    private struct ClipCatalog {
        var typeNames: [String] = []
        var sources: [String] = []
        var recentSources: [String] = []
    }

    @Published var query = ""
    @Published private(set) var clips: [ClipItem] = [] {
        didSet {
            clipsRevision &+= 1
            filteredCacheKey = nil
        }
    }
    @Published var selectedID: ClipItem.ID?
    @Published private(set) var isFocusVisible = false
    @Published var filter = ClipFilter() {
        didSet {
            guard oldValue != filter else { return }
            resetSelectionForVisibleClips()
        }
    }
    @Published var pinGroupSelection: PinGroupSelection = .all {
        didSet {
            guard oldValue != pinGroupSelection else { return }
            resetSelectionForVisibleClips()
        }
    }
    /// 仅在键盘 / 程序性选择时设置，驱动卡片墙滚动；鼠标点击不设置，避免点一下整排乱跑。
    @Published var scrollRequest: ScrollRequest?
    @Published var board: Board = .clipboard {
        didSet {
            guard oldValue != board else { return }
            selectedID = filteredClips.first?.id
            isFocusVisible = false
            scrollRequest = ScrollRequest(kind: .resetToFront)
        }
    }

    private var historyPolicy: HistoryPolicy {
        HistoryPolicy(
            maximumItemCount: AppSettings.shared.maxHistoryCount,
            retentionDays: AppSettings.shared.historyRetention.days
        )
    }
    private let pasteboard: NSPasteboard
    private let historyService: ClipHistoryService
    private let clipboardWriter: ClipboardWriter
    private var clipsRevision = 0
    private var filteredCacheKey: FilterCacheKey?
    private var filteredCache: [ClipItem] = []
    private var catalogRevision = -1
    private var catalog = ClipCatalog()
    private var monitoringStarted = false
    private lazy var clipboardMonitor = ClipboardMonitor(
        pasteboard: pasteboard,
        captureContext: { [weak self] in self?.currentCaptureContext() }
    ) { [weak self] capture, context in
        self?.addCapture(capture, context: context)
    }

    init(
        pasteboard: NSPasteboard = .general,
        historyService: ClipHistoryService = ClipHistoryService(
            store: try? ClipStore(
                historyPolicy: HistoryPolicy(
                    maximumItemCount: AppSettings.shared.maxHistoryCount,
                    retentionDays: AppSettings.shared.historyRetention.days
                )
            )
        )
    ) {
        self.pasteboard = pasteboard
        self.historyService = historyService
        clipboardWriter = ClipboardWriter(pasteboard: pasteboard)

        NotificationCenter.default.addObserver(
            forName: .clearHistoryRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let keepPinned = (notification.userInfo?["keepPinned"] as? Bool) ?? true
            Task { @MainActor in
                self?.clearHistory(keepPinned: keepPinned)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .historyPolicyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyHistoryPolicy()
            }
        }
    }

    var filteredClips: [ClipItem] {
        let timeBucket = filter.time == .all
            ? 0
            : Int(Date().timeIntervalSinceReferenceDate / 60)
        let key = FilterCacheKey(
            clipsRevision: clipsRevision,
            board: board,
            pinGroupSelection: pinGroupSelection,
            query: query,
            filter: filter,
            timeBucket: timeBucket
        )

        if filteredCacheKey != key {
            filteredCache = computeFilteredClips()
            filteredCacheKey = key
        }
        return filteredCache
    }

    private func computeFilteredClips() -> [ClipItem] {
        var boardClips = board == .pinned ? clips.filter(\.isPinned) : clips
        if board == .pinned {
            switch pinGroupSelection {
            case .all:
                break
            case .ungrouped:
                boardClips = boardClips.filter { $0.pinGroupID == nil }
            case .group(let groupID):
                boardClips = boardClips.filter { $0.pinGroupID == groupID }
            }
        }

        boardClips = boardClips.filter { filter.matches($0) }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return boardClips
        }

        // 各字段模糊打分，加权取最高分；分数越高越相关。
        let scored: [(clip: ClipItem, score: Int)] = boardClips.compactMap { clip in
            let candidates = [
                FuzzySearch.score(query: trimmedQuery, in: clip.displayTitle).map { $0 * 3 },
                FuzzySearch.score(query: trimmedQuery, in: clip.kind.displayName).map { $0 * 2 },
                FuzzySearch.score(query: trimmedQuery, in: clip.source).map { $0 * 2 },
                FuzzySearch.score(query: trimmedQuery, in: clip.preview),
            ].compactMap { $0 }

            var best = candidates.max()

            // 短字段都没命中时，对正文做一次子串兜底（命中深层长文本），给低分。
            if best == nil, clip.content.range(of: trimmedQuery, options: .caseInsensitive) != nil {
                best = 1
            }

            guard let best else { return nil }
            return (clip, best)
        }

        // 分数降序；同分按更新时间降序（更近的靠前）。
        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.clip.updatedAt > rhs.clip.updatedAt
            }
            .map(\.clip)
    }

    var pinnedClips: [ClipItem] {
        filteredClips.filter(\.isPinned)
    }

    var recentClips: [ClipItem] {
        filteredClips.filter { !$0.isPinned }
    }

    var availableTypeNames: [String] {
        refreshCatalogIfNeeded()
        return catalog.typeNames
    }

    var availableSources: [String] {
        refreshCatalogIfNeeded()
        return catalog.sources
    }

    var recentSources: [String] {
        refreshCatalogIfNeeded()
        return catalog.recentSources
    }

    private func refreshCatalogIfNeeded() {
        guard catalogRevision != clipsRevision else { return }

        var latestDates: [String: Date] = [:]
        for clip in clips {
            latestDates[clip.source] = max(latestDates[clip.source] ?? .distantPast, clip.updatedAt)
        }
        let recentSources = latestDates.keys.sorted { lhs, rhs in
            let leftDate = latestDates[lhs] ?? .distantPast
            let rightDate = latestDates[rhs] ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        catalog = ClipCatalog(
            typeNames: Array(Set(clips.map { $0.kind.displayName })).sorted(),
            sources: Array(Set(clips.map(\.source))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            },
            recentSources: recentSources
        )
        catalogRevision = clipsRevision
    }

    var activeFilterCount: Int {
        filter.activeCount
    }

    var activeFilterTokens: [ClipFilterToken] {
        filter.tokens
    }

    var filterSuggestions: [ClipFilterToken] {
        ClipFilterSuggestionEngine.suggestions(
            query: query,
            typeNames: availableTypeNames,
            sources: recentSources,
            activeFilter: filter
        )
    }

    var selectedPinGroupName: String {
        switch pinGroupSelection {
        case .all:
            "全部固定"
        case .ungrouped:
            "未分组"
        case .group(let id):
            AppSettings.shared.pinGroups.first(where: { $0.id == id })?.name ?? "未分组"
        }
    }

    var sensitiveFilteringEnabled: Bool {
        AppSettings.shared.sensitiveFiltering
    }

    var selectedClip: ClipItem? {
        guard let selectedID else {
            return filteredClips.first
        }

        return filteredClips.first { $0.id == selectedID }
    }

    var focusedClipID: ClipItem.ID? {
        isFocusVisible ? selectedID : nil
    }

    func startMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true
        clips = historyService.load()
        historyService.apply(historyPolicy, to: &clips)
        repairOrphanedPinGroups()
        backfillSourceBundleIDs()
        historyService.pruneOrphanedBlobs()
        clipboardMonitor.start()
        selectFirstIfNeeded()
    }

    /// 呼出面板时主动补抓一次剪贴板，保证刚复制的内容已在列表里（不必等下一次轮询）。
    func captureLatestNow() {
        clipboardMonitor.checkNow()
    }

    func prepareForPanelShow() {
        selectedID = filteredClips.first?.id
        isFocusVisible = false
        scrollRequest = ScrollRequest(kind: .resetToFront)
    }

    /// 一次性回填旧条目的来源 bundle id（功能上线前的历史没有它，导致无来源图标）。
    /// 来源 → bundle id 映射来自：已带 bundle id 的同源条目 + 当前运行的 App 名。
    private func backfillSourceBundleIDs() {
        var map: [String: String] = [:]

        for clip in clips where clip.sourceBundleID != nil {
            if map[clip.source] == nil {
                map[clip.source] = clip.sourceBundleID
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, let bundleID = app.bundleIdentifier else {
                continue
            }
            if map[name] == nil {
                map[name] = bundleID
            }
        }

        var updates: [(ClipItem.ID, String)] = []
        for index in clips.indices where clips[index].sourceBundleID == nil {
            if let bundleID = map[clips[index].source] {
                clips[index].sourceBundleID = bundleID
                updates.append((clips[index].id, bundleID))
            }
        }

        for (clipID, bundleID) in updates {
            historyService.updateSourceBundleID(clipID: clipID, bundleID: bundleID)
        }
    }

    private func currentCaptureContext() -> ClipboardCaptureContext? {
        guard !AppSettings.shared.isCapturePaused else {
            return nil
        }

        let frontmost = NSWorkspace.shared.frontmostApplication

        // 排除特定 App：来源在排除列表内则不采集。
        if
            let bundleID = frontmost?.bundleIdentifier,
            AppSettings.shared.excludedBundleIDs.contains(bundleID)
        {
            return nil
        }

        return ClipboardCaptureContext(
            source: frontmost?.localizedName ?? "剪贴板",
            sourceBundleID: frontmost?.bundleIdentifier
        )
    }

    private func addCapture(_ capture: ClipboardCapture, context: ClipboardCaptureContext) {
        // 读取期间用户可能刚好开启暂停，入库前再做一次轻量复核。
        guard !AppSettings.shared.isCapturePaused else {
            return
        }
        if
            let bundleID = context.sourceBundleID,
            AppSettings.shared.excludedBundleIDs.contains(bundleID)
        {
            return
        }

        guard historyService.register(
            capture,
            context: context,
            sensitiveFiltering: AppSettings.shared.sensitiveFiltering,
            storeSensitivePlaceholder: AppSettings.shared.storeSensitivePlaceholder,
            clips: &clips,
            policy: historyPolicy
        ) else {
            return
        }

        selectedID = filteredClips.first?.id
        isFocusVisible = false
        scrollRequest = ScrollRequest(kind: .resetToFront)
    }

    func selectNext() {
        moveSelection(offset: 1)
        requestRevealSelection()
    }

    func selectPrevious() {
        moveSelection(offset: -1)
        requestRevealSelection()
    }

    private func requestRevealSelection() {
        guard let selectedID else { return }
        scrollRequest = ScrollRequest(kind: .reveal(selectedID))
    }

    func setTypeFilter(_ typeName: String?) {
        filter.typeName = typeName
    }

    func setSourceFilter(_ source: String?) {
        filter.source = source
    }

    func setTimeFilter(_ time: ClipTimeFilter) {
        filter.time = time
    }

    func applyFilterToken(_ token: ClipFilterToken) {
        filter.apply(token)
    }

    func removeFilterToken(_ token: ClipFilterToken) {
        filter.remove(token)
    }

    func toggleFilterToken(_ token: ClipFilterToken) {
        if filter.tokens.contains(token) {
            filter.remove(token)
        } else {
            filter.apply(token)
        }
    }

    func removeLastFilterToken() {
        guard let token = filter.tokens.last else { return }
        filter.remove(token)
    }

    func clearFilters() {
        filter = ClipFilter()
    }

    func clearSearchAndFilters() {
        query = ""
        clearFilters()
    }

    func sourceBundleID(for source: String) -> String? {
        clips.first(where: { $0.source == source && $0.sourceBundleID != nil })?.sourceBundleID
    }

    func selectPinGroup(_ selection: PinGroupSelection) {
        pinGroupSelection = selection
    }

    /// 与 Return 一致：未按过方向键时作用于第一张（selectedClip 的兜底），不再静默无效。
    func togglePinSelected() {
        guard let selectedClip else {
            return
        }

        togglePin(clipID: selectedClip.id)
    }

    func togglePin(clipID: ClipItem.ID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return
        }

        selectedID = clipID
        clips[index].isPinned.toggle()
        if clips[index].isPinned {
            if case .group(let groupID) = pinGroupSelection, board == .pinned {
                clips[index].pinGroupID = groupID
            }
        } else {
            clips[index].pinGroupID = nil
        }
        historyService.updatePin(for: clips[index])
    }

    func renamePinnedClip(clipID: ClipItem.ID, to rawName: String) {
        guard
            let index = clips.firstIndex(where: { $0.id == clipID }),
            clips[index].isPinned
        else {
            return
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        clips[index].customName = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
        historyService.updateCustomName(for: clips[index])
    }

    func movePinnedClip(clipID: ClipItem.ID, to groupID: UUID?) {
        guard
            let index = clips.firstIndex(where: { $0.id == clipID }),
            clips[index].isPinned
        else {
            return
        }

        clips[index].pinGroupID = groupID
        historyService.updatePin(for: clips[index])
    }

    @discardableResult
    func createPinGroup(named name: String) -> PinGroup? {
        guard let group = AppSettings.shared.createPinGroup(named: name) else { return nil }
        board = .pinned
        pinGroupSelection = .group(group.id)
        return group
    }

    func renamePinGroup(id: UUID, to name: String) {
        AppSettings.shared.renamePinGroup(id: id, to: name)
    }

    func deletePinGroup(id: UUID) {
        for index in clips.indices where clips[index].pinGroupID == id {
            clips[index].pinGroupID = nil
        }

        historyService.clearPinGroup(id: id)

        AppSettings.shared.deletePinGroup(id: id)
        if pinGroupSelection == .group(id) {
            pinGroupSelection = .ungrouped
        }
    }

    /// 与 Return 一致：未按过方向键时作用于第一张（selectedClip 的兜底），不再静默无效。
    func deleteSelected() {
        guard let selectedClip else {
            return
        }

        delete(clipID: selectedClip.id)
    }

    func select(clipID: ClipItem.ID, revealFocus: Bool = true) {
        selectedID = clipID
        isFocusVisible = revealFocus
    }

    func delete(clipID: ClipItem.ID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return
        }

        // 删除后把选中移到相邻项，保持键盘流不中断。
        let visibleBefore = filteredClips
        let removedVisibleIndex = visibleBefore.firstIndex(where: { $0.id == clipID })

        historyService.delete(clips[index], from: &clips)

        let visibleAfter = filteredClips
        if let removedVisibleIndex {
            let nextIndex = min(removedVisibleIndex, visibleAfter.count - 1)
            selectedID = nextIndex >= 0 ? visibleAfter[nextIndex].id : nil
        } else {
            selectedID = visibleAfter.first?.id
        }
    }

    func clearHistory(keepPinned: Bool) {
        historyService.clear(keepPinned: keepPinned, clips: &clips)
        selectedID = filteredClips.first?.id
        isFocusVisible = false
    }

    @discardableResult
    func pasteSelected(mode: PasteMode = .original) -> Bool {
        guard let selectedClip, clipboardWriter.write(selectedClip, mode: mode) else { return false }
        clipboardMonitor.syncToCurrentChangeCount()
        return true
    }

    func handleQueryChange() {
        resetSelectionForVisibleClips()
    }

    private func resetSelectionForVisibleClips() {
        selectedID = filteredClips.first?.id
        isFocusVisible = false
        scrollRequest = ScrollRequest(kind: .resetToFront)
    }
    private func selectFirstIfNeeded() {
        if selectedID == nil || selectedClip == nil {
            selectedID = filteredClips.first?.id
            scrollRequest = ScrollRequest(kind: .resetToFront)
        }
    }

    /// 偏好被重置但数据库仍保留时，避免条目指向不存在的分组而无法在「未分组」中找到。
    private func repairOrphanedPinGroups() {
        let validGroupIDs = Set(AppSettings.shared.pinGroups.map(\.id))

        for index in clips.indices {
            guard
                let groupID = clips[index].pinGroupID,
                !validGroupIDs.contains(groupID)
            else {
                continue
            }

            clips[index].pinGroupID = nil
            historyService.updatePin(for: clips[index])
        }
    }

    private func applyHistoryPolicy() {
        historyService.apply(historyPolicy, to: &clips)

        selectedID = filteredClips.first?.id
        scrollRequest = ScrollRequest(kind: .resetToFront)
    }

    private func moveSelection(offset: Int) {
        let visibleClips = filteredClips

        guard !visibleClips.isEmpty else {
            selectedID = nil
            isFocusVisible = false
            return
        }

        guard isFocusVisible else {
            selectedID = visibleClips.first?.id
            isFocusVisible = true
            return
        }

        guard let selectedID, let currentIndex = visibleClips.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = visibleClips.first?.id
            isFocusVisible = true
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), visibleClips.count - 1)
        self.selectedID = visibleClips[nextIndex].id
    }
}
