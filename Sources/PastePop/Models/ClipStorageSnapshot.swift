import Foundation

struct ClipStorageSnapshot: Equatable {
    let clipCount: Int
    let attachmentBytes: Int64

    static func current() -> ClipStorageSnapshot {
        ClipStorageSnapshot(
            clipCount: ClipStore.storedClipCount(),
            attachmentBytes: ClipBlobStore.totalSize()
        )
    }

    var summary: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesActualByteCount = false
        let currentSize = formatter.string(fromByteCount: attachmentBytes)
        let maximumSize = formatter.string(fromByteCount: HistoryPolicy.defaultMaximumAttachmentBytes)
        return "本机历史 \(clipCount) 条 · 附件 \(currentSize) / \(maximumSize)"
    }
}
