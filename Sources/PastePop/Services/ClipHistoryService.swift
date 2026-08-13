import Foundation

/// 负责剪贴板捕获进入历史后的完整生命周期：分类、敏感保护、去重、持久化与淘汰。
@MainActor
final class ClipHistoryService {
    struct BlobAccess {
        let write: (Data, String) -> Bool
        let delete: (String) -> Void
        let size: (String) -> Int64
        let deleteOrphans: (Set<String>) -> Void

        @MainActor static let live = BlobAccess(
            write: { ClipBlobStore.write($0, filename: $1) },
            delete: { ClipBlobStore.delete(filename: $0) },
            size: { ClipBlobStore.size(filename: $0) },
            deleteOrphans: { ClipBlobStore.deleteOrphans(keeping: $0) }
        )
    }

    private let store: ClipStore?
    private let blobs: BlobAccess

    init(store: ClipStore?, blobs: BlobAccess = .live) {
        self.store = store
        self.blobs = blobs
    }

    func load() -> [ClipItem] {
        guard let store else { return [] }

        do {
            return try store.fetchClips()
        } catch {
            AppLogger.storage.error("加载历史失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @discardableResult
    func register(
        _ capture: ClipboardCapture,
        context: ClipboardCaptureContext,
        sensitiveFiltering: Bool,
        storeSensitivePlaceholder: Bool,
        clips: inout [ClipItem],
        policy: HistoryPolicy
    ) -> Bool {
        switch capture {
        case .text(let text):
            guard let registration = makeTextRegistration(
                text,
                context: context,
                sensitiveFiltering: sensitiveFiltering,
                storeSensitivePlaceholder: storeSensitivePlaceholder
            ) else {
                return false
            }
            return register(registration.clip, blob: registration.blob, clips: &clips, policy: policy)

        case .richText(let rtf, let plain):
            guard let registration = makeRichTextRegistration(
                rtf: rtf,
                plain: plain,
                context: context,
                sensitiveFiltering: sensitiveFiltering,
                storeSensitivePlaceholder: storeSensitivePlaceholder
            ) else {
                return false
            }
            return register(registration.clip, blob: registration.blob, clips: &clips, policy: policy)

        case .image(let png, let pixelSize):
            let clip = ClipClassifier.makeImageClip(
                png: png,
                pixelSize: pixelSize,
                source: context.source,
                sourceBundleID: context.sourceBundleID
            )
            return register(clip, blob: png, clips: &clips, policy: policy)

        case .files(let urls):
            guard let clip = ClipClassifier.makeFileClip(
                urls: urls,
                source: context.source,
                sourceBundleID: context.sourceBundleID
            ) else {
                return false
            }
            return register(clip, clips: &clips, policy: policy)
        }
    }

    func apply(_ policy: HistoryPolicy, to clips: inout [ClipItem]) {
        let locallyRemoved = removeItems(matching: policy, from: &clips)

        guard let store else {
            deleteAttachments(for: locallyRemoved)
            postStorageDidChangeIfNeeded(!locallyRemoved.isEmpty)
            return
        }

        do {
            let persistedRemoved = try store.updateHistoryPolicy(policy)
            locallyRemoved.forEach { deletePersistedClip($0.id) }
            deleteAttachments(for: locallyRemoved + persistedRemoved)
            postStorageDidChangeIfNeeded(!locallyRemoved.isEmpty || !persistedRemoved.isEmpty)
        } catch {
            AppLogger.storage.error("应用历史策略失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func pruneOrphanedBlobs() {
        guard let store else { return }

        do {
            blobs.deleteOrphans(try store.fetchAttachmentFilenames())
        } catch {
            AppLogger.storage.error("清理孤立附件失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func updateSourceBundleID(clipID: ClipItem.ID, bundleID: String) {
        do {
            try store?.updateSourceBundleID(clipID: clipID, bundleID: bundleID)
        } catch {
            AppLogger.storage.error("回填来源 App 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func updatePin(for clip: ClipItem) {
        do {
            try store?.updatePin(
                clipID: clip.id,
                isPinned: clip.isPinned,
                pinGroupID: clip.pinGroupID
            )
            postStorageDidChange()
        } catch {
            AppLogger.storage.error("保存固定状态失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func updateCustomName(for clip: ClipItem) {
        do {
            try store?.updateCustomName(clipID: clip.id, customName: clip.customName)
        } catch {
            AppLogger.storage.error("保存自定义名称失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func clearPinGroup(id: UUID) {
        do {
            try store?.clearPinGroup(groupID: id)
        } catch {
            AppLogger.storage.error("清理固定分组失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ clip: ClipItem, from clips: inout [ClipItem]) {
        if let filename = clip.attachmentFilename {
            blobs.delete(filename)
        }
        clips.removeAll { $0.id == clip.id }
        deletePersistedClip(clip.id)
        postStorageDidChange()
    }

    func clear(keepPinned: Bool, clips: inout [ClipItem]) {
        let removed = keepPinned ? clips.filter { !$0.isPinned } : clips
        deleteAttachments(for: removed)
        clips = keepPinned ? clips.filter(\.isPinned) : []

        do {
            try store?.clear(keepPinned: keepPinned)
            postStorageDidChange()
        } catch {
            AppLogger.storage.error("清空历史失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeTextRegistration(
        _ text: String,
        context: ClipboardCaptureContext,
        sensitiveFiltering: Bool,
        storeSensitivePlaceholder: Bool
    ) -> Registration? {
        if sensitiveFiltering, SensitiveContentFilter.isSensitive(text) {
            guard storeSensitivePlaceholder else { return nil }
            return Registration(
                clip: ClipClassifier.makeMaskedSecret(
                    source: context.source,
                    sourceBundleID: context.sourceBundleID
                )
            )
        }

        guard let clip = ClipClassifier.makeClip(
            from: text,
            source: context.source,
            sourceBundleID: context.sourceBundleID
        ) else {
            return nil
        }
        return Registration(clip: clip)
    }

    private func makeRichTextRegistration(
        rtf: Data,
        plain: String,
        context: ClipboardCaptureContext,
        sensitiveFiltering: Bool,
        storeSensitivePlaceholder: Bool
    ) -> Registration? {
        if sensitiveFiltering, SensitiveContentFilter.isSensitive(plain) {
            guard storeSensitivePlaceholder else { return nil }
            return Registration(
                clip: ClipClassifier.makeMaskedSecret(
                    source: context.source,
                    sourceBundleID: context.sourceBundleID
                )
            )
        }

        guard let clip = ClipClassifier.makeRichTextClip(
            rtf: rtf,
            plain: plain,
            source: context.source,
            sourceBundleID: context.sourceBundleID
        ) else {
            return nil
        }
        return Registration(clip: clip, blob: rtf)
    }

    @discardableResult
    private func register(
        _ clip: ClipItem,
        blob: Data? = nil,
        clips: inout [ClipItem],
        policy: HistoryPolicy
    ) -> Bool {
        var newClip = clip
        var isDuplicate = false

        if let existingIndex = clips.firstIndex(where: {
            $0.content == newClip.content && $0.isSensitive == newClip.isSensitive
        }) {
            var existing = clips.remove(at: existingIndex)
            existing.updatedAt = Date()
            newClip = existing
            isDuplicate = true
        }

        if !isDuplicate, let blob, let filename = newClip.attachmentFilename {
            guard blobs.write(blob, filename) else { return false }
        }

        clips.insert(newClip, at: 0)
        let locallyRemoved = removeItems(matching: policy, from: &clips)

        if let persistedRemoved = persist(newClip) {
            locallyRemoved.forEach { deletePersistedClip($0.id) }
            deleteAttachments(for: locallyRemoved + persistedRemoved)
        }
        postStorageDidChange()
        return true
    }

    private func removeItems(
        matching policy: HistoryPolicy,
        from clips: inout [ClipItem]
    ) -> [ClipItem] {
        let removed = policy.itemsToRemove(
            from: clips,
            attachmentSize: blobs.size
        )
        let removedIDs = Set(removed.map(\.id))
        clips.removeAll { removedIDs.contains($0.id) }
        return removed
    }

    private func persist(_ clip: ClipItem) -> [ClipItem]? {
        guard let store else { return [] }

        do {
            return try store.upsert(clip)
        } catch {
            AppLogger.storage.error("保存历史失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func deletePersistedClip(_ clipID: ClipItem.ID) {
        do {
            try store?.delete(clipID: clipID)
        } catch {
            AppLogger.storage.error("删除历史失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteAttachments(for clips: [ClipItem]) {
        for clip in clips {
            if let filename = clip.attachmentFilename {
                blobs.delete(filename)
            }
        }
    }

    private func postStorageDidChangeIfNeeded(_ needed: Bool) {
        guard needed else { return }
        postStorageDidChange()
    }

    private func postStorageDidChange() {
        NotificationCenter.default.post(name: .historyStorageDidChange, object: nil)
    }
}

private struct Registration {
    let clip: ClipItem
    let blob: Data?

    init(clip: ClipItem, blob: Data? = nil) {
        self.clip = clip
        self.blob = blob
    }
}
