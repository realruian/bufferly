import Foundation
import Testing
@testable import PastePop

@Suite("ClipHistoryService")
struct ClipHistoryServiceTests {
    @Test("重复文本复用原条目并移动到最前")
    @MainActor
    func deduplicatesTextCaptures() throws {
        let service = ClipHistoryService(store: nil, blobs: makeBlobAccess())
        let context = ClipboardCaptureContext(source: "Tests", sourceBundleID: nil)
        let policy = HistoryPolicy(maximumItemCount: 100, retentionDays: nil)
        var clips: [ClipItem] = []

        #expect(service.register(
            .text("第一条"),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: policy
        ))
        let firstID = try #require(clips.first?.id)

        #expect(service.register(
            .text("第二条"),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: policy
        ))
        #expect(service.register(
            .text("第一条"),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: policy
        ))

        #expect(clips.count == 2)
        #expect(clips.first?.id == firstID)
    }

    @Test("关闭提示卡片时敏感内容完全不进入历史")
    @MainActor
    func dropsSensitiveContentWithoutPlaceholder() {
        let service = ClipHistoryService(store: nil, blobs: makeBlobAccess())
        let context = ClipboardCaptureContext(source: "Tests", sourceBundleID: nil)
        var clips: [ClipItem] = []

        let registered = service.register(
            .text("OPENAI_API_KEY=sk-Ab3dEf6hIj9kLm2nOp5qRs8tUv1w"),
            context: context,
            sensitiveFiltering: true,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: HistoryPolicy(maximumItemCount: 100, retentionDays: nil)
        )

        #expect(!registered)
        #expect(clips.isEmpty)
    }

    @Test("图片去重不产生孤立附件，删除记录会同步删除附件")
    @MainActor
    func managesAttachmentLifecycle() throws {
        var writtenFilenames: [String] = []
        var deletedFilenames: [String] = []
        var storedSizes: [String: Int64] = [:]
        let blobs = ClipHistoryService.BlobAccess(
            write: { data, filename in
                writtenFilenames.append(filename)
                storedSizes[filename] = Int64(data.count)
                return true
            },
            delete: { filename in
                deletedFilenames.append(filename)
                storedSizes.removeValue(forKey: filename)
            },
            size: { storedSizes[$0] ?? 0 },
            deleteOrphans: { _ in }
        )
        let service = ClipHistoryService(store: nil, blobs: blobs)
        let context = ClipboardCaptureContext(source: "Tests", sourceBundleID: nil)
        let policy = HistoryPolicy(maximumItemCount: 100, retentionDays: nil)
        let imageData = Data([1, 2, 3, 4])
        var clips: [ClipItem] = []

        #expect(service.register(
            .image(png: imageData, pixelSize: nil),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: policy
        ))
        #expect(service.register(
            .image(png: imageData, pixelSize: nil),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: policy
        ))

        let clip = try #require(clips.first)
        let filename = try #require(clip.attachmentFilename)
        #expect(clips.count == 1)
        #expect(writtenFilenames == [filename])

        service.delete(clip, from: &clips)
        #expect(clips.isEmpty)
        #expect(deletedFilenames == [filename])
    }

    @Test("附件写入失败时不生成不可用历史")
    @MainActor
    func rejectsCaptureWhenAttachmentWriteFails() {
        let blobs = ClipHistoryService.BlobAccess(
            write: { _, _ in false },
            delete: { _ in },
            size: { _ in 0 },
            deleteOrphans: { _ in }
        )
        let service = ClipHistoryService(store: nil, blobs: blobs)
        let context = ClipboardCaptureContext(source: "Tests", sourceBundleID: nil)
        var clips: [ClipItem] = []

        let registered = service.register(
            .image(png: Data([1, 2, 3]), pixelSize: nil),
            context: context,
            sensitiveFiltering: false,
            storeSensitivePlaceholder: false,
            clips: &clips,
            policy: HistoryPolicy(maximumItemCount: 100, retentionDays: nil)
        )

        #expect(!registered)
        #expect(clips.isEmpty)
    }

    @MainActor
    private func makeBlobAccess() -> ClipHistoryService.BlobAccess {
        ClipHistoryService.BlobAccess(
            write: { _, _ in true },
            delete: { _ in },
            size: { _ in 0 },
            deleteOrphans: { _ in }
        )
    }
}
