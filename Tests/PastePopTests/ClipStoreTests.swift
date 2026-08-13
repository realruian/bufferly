import Foundation
import Testing
@testable import PastePop

@Suite("ClipStore")
struct ClipStoreTests {
    @Test("固定内容名称和分组会持久化")
    func persistsPinMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastePopTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try ClipStore(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let clip = ClipItem(
            kind: .text,
            title: "自动标题",
            preview: "公司地址",
            source: "Notes",
            content: "上海市测试路 1 号"
        )
        let groupID = UUID()

        try store.upsert(clip)
        try store.updatePin(clipID: clip.id, isPinned: true, pinGroupID: groupID)
        try store.updateCustomName(clipID: clip.id, customName: "公司地址")

        let stored = try #require(store.fetchClips().first)
        #expect(stored.isPinned)
        #expect(stored.pinGroupID == groupID)
        #expect(stored.customName == "公司地址")

        try store.clearPinGroup(groupID: groupID)
        #expect(try #require(store.fetchClips().first).pinGroupID == nil)
    }

    @Test("历史策略清理旧内容但保留固定内容")
    func appliesHistoryPolicyWithoutRemovingPinnedItems() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastePopTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try ClipStore(
            historyPolicy: HistoryPolicy(maximumItemCount: 2, retentionDays: nil),
            databaseURL: directory.appendingPathComponent("clips.sqlite")
        )
        let pinned = makeClip(content: "固定", updatedAt: Date().addingTimeInterval(-300), isPinned: true)
        let old = makeClip(content: "旧内容", updatedAt: Date().addingTimeInterval(-200))
        let recent = makeClip(content: "新内容", updatedAt: Date().addingTimeInterval(-100))

        try store.upsert(pinned)
        try store.upsert(old)
        let removed = try store.upsert(recent)

        #expect(removed.map(\.id) == [old.id])
        #expect(Set(try store.fetchClips().map(\.id)) == Set([pinned.id, recent.id]))
    }

    private func makeClip(content: String, updatedAt: Date, isPinned: Bool = false) -> ClipItem {
        ClipItem(
            kind: .text,
            title: content,
            preview: content,
            source: "Tests",
            content: content,
            updatedAt: updatedAt,
            isPinned: isPinned
        )
    }
}
