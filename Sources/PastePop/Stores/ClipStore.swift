import Foundation
import GRDB

final class ClipStore {
    /// 数据库文件路径；目录不可用时为 nil，由界面层决定显示文案。
    static var databasePath: String? {
        try? databaseURL().path
    }

    static func storedClipCount() -> Int {
        guard
            let databaseURL = try? databaseURL(),
            FileManager.default.fileExists(atPath: databaseURL.path),
            let queue = try? DatabaseQueue(path: databaseURL.path)
        else {
            return 0
        }

        return (try? queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips") ?? 0
        }) ?? 0
    }

    private let dbQueue: DatabaseQueue
    private var historyPolicy: HistoryPolicy

    init(
        historyPolicy: HistoryPolicy = HistoryPolicy(maximumItemCount: 500, retentionDays: nil),
        databaseURL: URL? = nil
    ) throws {
        self.historyPolicy = historyPolicy
        let databaseURL = try databaseURL ?? Self.databaseURL()
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try migrate()
    }

    func fetchClips() throws -> [ClipItem] {
        try dbQueue.write { db in
            _ = try pruneExpiredIfNeeded(db)

            let pinned = try ClipRecord
                .filter(Column("isPinned") == true)
                .order(Column("updatedAt").desc)
                .fetchAll(db)

            let unpinnedLimit = max(0, historyPolicy.maximumItemCount - pinned.count)
            let unpinned = try ClipRecord
                .filter(Column("isPinned") == false)
                .order(Column("isPinned").desc, Column("updatedAt").desc)
                .limit(unpinnedLimit)
                .fetchAll(db)

            return (pinned + unpinned).map(\.clipItem)
        }
    }

    @discardableResult
    func upsert(_ clip: ClipItem) throws -> [ClipItem] {
        try dbQueue.write { db in
            var record = ClipRecord(clip)
            try record.save(db)
            let expired = try pruneExpiredIfNeeded(db)
            let overflow = try pruneIfNeeded(db)
            return expired + overflow
        }
    }

    func updateHistoryPolicy(_ historyPolicy: HistoryPolicy) throws -> [ClipItem] {
        self.historyPolicy = historyPolicy

        return try dbQueue.write { db in
            let expired = try pruneExpiredIfNeeded(db)
            let overflow = try pruneIfNeeded(db)
            return expired + overflow
        }
    }

    func updatePin(clipID: ClipItem.ID, isPinned: Bool, pinGroupID: UUID?) throws {
        _ = try dbQueue.write { db in
            try ClipRecord
                .filter(Column("id") == clipID.uuidString)
                .updateAll(
                    db,
                    Column("isPinned").set(to: isPinned),
                    Column("pinGroupID").set(to: pinGroupID?.uuidString)
                )
        }
    }

    func updateCustomName(clipID: ClipItem.ID, customName: String?) throws {
        _ = try dbQueue.write { db in
            try ClipRecord
                .filter(Column("id") == clipID.uuidString)
                .updateAll(db, Column("customName").set(to: customName))
        }
    }

    func clearPinGroup(groupID: UUID) throws {
        _ = try dbQueue.write { db in
            try ClipRecord
                .filter(Column("pinGroupID") == groupID.uuidString)
                .updateAll(db, Column("pinGroupID").set(to: nil))
        }
    }

    func updateSourceBundleID(clipID: ClipItem.ID, bundleID: String) throws {
        _ = try dbQueue.write { db in
            try ClipRecord
                .filter(Column("id") == clipID.uuidString)
                .updateAll(db, Column("sourceBundleID").set(to: bundleID))
        }
    }

    func delete(clipID: ClipItem.ID) throws {
        _ = try dbQueue.write { db in
            try ClipRecord
                .filter(Column("id") == clipID.uuidString)
                .deleteAll(db)
        }
    }

    /// 清空历史。`keepPinned` 为真时保留已固定片段。
    func clear(keepPinned: Bool) throws {
        _ = try dbQueue.write { db in
            if keepPinned {
                try ClipRecord
                    .filter(Column("isPinned") == false)
                    .deleteAll(db)
            } else {
                try ClipRecord.deleteAll(db)
            }
        }
    }

    func fetchAttachmentFilenames() throws -> Set<String> {
        try dbQueue.read { db in
            let filenames = try String.fetchAll(
                db,
                sql: """
                SELECT attachmentFilename
                FROM clips
                WHERE attachmentFilename IS NOT NULL
                """
            )
            return Set(filenames)
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createClips") { db in
            try db.create(table: "clips", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull().unique(onConflict: .replace)
                table.column("kind", .text).notNull()
                table.column("title", .text).notNull()
                table.column("preview", .text).notNull()
                table.column("source", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull().indexed()
                table.column("isPinned", .boolean).notNull().defaults(to: false).indexed()
                table.column("isSensitive", .boolean).notNull().defaults(to: false)
            }
        }

        // 图片 / 文件 / 富文本附件：blob 文件名 + 回写用的 pasteboard 类型。
        migrator.registerMigration("addAttachments") { db in
            try db.alter(table: "clips") { table in
                table.add(column: "attachmentFilename", .text)
                table.add(column: "attachmentUTI", .text)
            }
        }

        // 来源 App 的 bundle id，用于卡片显示来源图标。
        migrator.registerMigration("addSourceBundleID") { db in
            try db.alter(table: "clips") { table in
                table.add(column: "sourceBundleID", .text)
            }
        }

        // 固定内容的用户名称与单层分组；旧数据保持 nil，即「未分组」。
        migrator.registerMigration("addPinMetadata") { db in
            try db.alter(table: "clips") { table in
                table.add(column: "customName", .text)
                table.add(column: "pinGroupID", .text).indexed()
            }
        }

        try migrator.migrate(dbQueue)
    }

    private func pruneIfNeeded(_ db: Database) throws -> [ClipItem] {
        let totalCount = try ClipRecord.fetchCount(db)

        guard totalCount > historyPolicy.maximumItemCount else {
            return []
        }

        let removableIDs = try String.fetchAll(
            db,
            sql: """
            SELECT id
            FROM clips
            WHERE isPinned = 0
            ORDER BY updatedAt ASC
            LIMIT ?
            """,
            arguments: [totalCount - historyPolicy.maximumItemCount]
        )

        guard !removableIDs.isEmpty else {
            return []
        }

        let removableRecords = try ClipRecord
            .filter(removableIDs.contains(Column("id")))
            .fetchAll(db)

        try ClipRecord
            .filter(removableIDs.contains(Column("id")))
            .deleteAll(db)

        return removableRecords.map(\.clipItem)
    }

    private func pruneExpiredIfNeeded(_ db: Database) throws -> [ClipItem] {
        guard let cutoffDate = historyPolicy.expirationCutoff() else {
            return []
        }

        let removableRecords = try ClipRecord
            .filter(Column("isPinned") == false)
            .filter(Column("updatedAt") < cutoffDate)
            .fetchAll(db)

        guard !removableRecords.isEmpty else {
            return []
        }

        let removableIDs = removableRecords.map(\.id)
        try ClipRecord
            .filter(removableIDs.contains(Column("id")))
            .deleteAll(db)

        return removableRecords.map(\.clipItem)
    }

    private static func databaseURL() throws -> URL {
        try AppDataLocation.databaseURL()
    }
}

private struct ClipRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clips"

    var id: String
    var content: String
    var kind: String
    var title: String
    var customName: String?
    var preview: String
    var source: String
    var sourceBundleID: String?
    var attachmentFilename: String?
    var attachmentUTI: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var pinGroupID: String?
    var isSensitive: Bool

    init(_ clip: ClipItem) {
        id = clip.id.uuidString
        content = clip.content
        kind = clip.kind.rawValue
        title = clip.title
        customName = clip.customName
        preview = clip.preview
        source = clip.source
        sourceBundleID = clip.sourceBundleID
        attachmentFilename = clip.attachmentFilename
        attachmentUTI = clip.attachmentUTI
        createdAt = clip.createdAt
        updatedAt = clip.updatedAt
        isPinned = clip.isPinned
        pinGroupID = clip.pinGroupID?.uuidString
        isSensitive = clip.isSensitive
    }

    var clipItem: ClipItem {
        ClipItem(
            id: UUID(uuidString: id) ?? UUID(),
            kind: ClipKind(rawValue: kind) ?? .text,
            title: title,
            customName: customName,
            preview: preview,
            source: source,
            sourceBundleID: sourceBundleID,
            content: content,
            attachmentFilename: attachmentFilename,
            attachmentUTI: attachmentUTI,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            pinGroupID: pinGroupID.flatMap(UUID.init(uuidString:)),
            isSensitive: isSensitive
        )
    }
}
