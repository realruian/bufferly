import Foundation

/// 历史记录的统一淘汰策略。固定内容不参与时间、数量和附件容量淘汰。
struct HistoryPolicy: Equatable {
    static let defaultMaximumAttachmentBytes: Int64 = 200 * 1_024 * 1_024

    let maximumItemCount: Int
    let retentionDays: Int?
    let maximumAttachmentBytes: Int64

    init(
        maximumItemCount: Int,
        retentionDays: Int?,
        maximumAttachmentBytes: Int64 = Self.defaultMaximumAttachmentBytes
    ) {
        self.maximumItemCount = maximumItemCount
        self.retentionDays = retentionDays
        self.maximumAttachmentBytes = maximumAttachmentBytes
    }

    func expirationCutoff(now: Date = Date()) -> Date? {
        guard let retentionDays, retentionDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)
    }

    /// 返回应该删除的条目，顺序为：过期、超出数量、超出附件容量。
    func itemsToRemove(
        from clips: [ClipItem],
        attachmentSize: (String) -> Int64 = { _ in 0 },
        now: Date = Date()
    ) -> [ClipItem] {
        var retained = clips
        var removed: [ClipItem] = []

        if let cutoff = expirationCutoff(now: now) {
            let expiredIDs = Set(
                retained
                    .filter { !$0.isPinned && $0.updatedAt < cutoff }
                    .map(\.id)
            )
            remove(expiredIDs, from: &retained, appendingTo: &removed)
        }

        let overflow = retained.count - maximumItemCount
        if overflow > 0 {
            let overflowIDs = Set(
                retained
                    .filter { !$0.isPinned }
                    .sorted { $0.updatedAt < $1.updatedAt }
                    .prefix(overflow)
                    .map(\.id)
            )
            remove(overflowIDs, from: &retained, appendingTo: &removed)
        }

        var attachmentBytes = retained.reduce(into: Int64(0)) { total, clip in
            guard let filename = clip.attachmentFilename else { return }
            total += max(0, attachmentSize(filename))
        }

        if attachmentBytes > maximumAttachmentBytes {
            for clip in retained
                .filter({ !$0.isPinned && $0.attachmentFilename != nil })
                .sorted(by: { $0.updatedAt < $1.updatedAt })
            {
                guard attachmentBytes > maximumAttachmentBytes else { break }
                guard let filename = clip.attachmentFilename else { continue }
                attachmentBytes -= max(0, attachmentSize(filename))
                removed.append(clip)
                retained.removeAll { $0.id == clip.id }
            }
        }

        return removed
    }

    private func remove(
        _ ids: Set<ClipItem.ID>,
        from retained: inout [ClipItem],
        appendingTo removed: inout [ClipItem]
    ) {
        guard !ids.isEmpty else { return }
        removed.append(contentsOf: retained.filter { ids.contains($0.id) })
        retained.removeAll { ids.contains($0.id) }
    }
}
