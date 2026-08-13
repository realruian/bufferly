import Foundation
import Testing
@testable import PastePop

@Suite("HistoryPolicy")
struct HistoryPolicyTests {
    @Test("过期和超量清理始终保留固定内容")
    func removesExpiredAndOverflowClipsWithoutRemovingPinnedItems() {
        let now = Date()
        let pinned = makeClip(title: "固定", updatedAt: now.addingTimeInterval(-30 * 86_400), isPinned: true)
        let expired = makeClip(title: "过期", updatedAt: now.addingTimeInterval(-8 * 86_400))
        let old = makeClip(title: "较旧", updatedAt: now.addingTimeInterval(-300))
        let recent = makeClip(title: "最新", updatedAt: now.addingTimeInterval(-60))
        let policy = HistoryPolicy(maximumItemCount: 2, retentionDays: 7)

        let removed = policy.itemsToRemove(from: [pinned, expired, old, recent], now: now)

        #expect(Set(removed.map(\.id)) == Set([expired.id, old.id]))
    }

    @Test("附件超过总容量时从最旧的未固定内容开始清理")
    func removesOldestUnpinnedAttachmentsWhenStorageBudgetIsExceeded() {
        let now = Date()
        let pinned = makeClip(
            title: "固定图片",
            updatedAt: now.addingTimeInterval(-400),
            isPinned: true,
            attachmentFilename: "pinned.png"
        )
        let old = makeClip(
            title: "旧图片",
            updatedAt: now.addingTimeInterval(-300),
            attachmentFilename: "old.png"
        )
        let recent = makeClip(
            title: "新图片",
            updatedAt: now.addingTimeInterval(-100),
            attachmentFilename: "recent.png"
        )
        let sizes: [String: Int64] = [
            "pinned.png": 40,
            "old.png": 40,
            "recent.png": 40,
        ]
        let policy = HistoryPolicy(
            maximumItemCount: 100,
            retentionDays: nil,
            maximumAttachmentBytes: 90
        )

        let removed = policy.itemsToRemove(
            from: [pinned, old, recent],
            attachmentSize: { sizes[$0] ?? 0 },
            now: now
        )

        #expect(removed.map(\.id) == [old.id])
    }

    private func makeClip(
        title: String,
        updatedAt: Date,
        isPinned: Bool = false,
        attachmentFilename: String? = nil
    ) -> ClipItem {
        ClipItem(
            kind: attachmentFilename == nil ? .text : .image,
            title: title,
            preview: title,
            source: "Tests",
            content: title,
            attachmentFilename: attachmentFilename,
            updatedAt: updatedAt,
            isPinned: isPinned
        )
    }
}
