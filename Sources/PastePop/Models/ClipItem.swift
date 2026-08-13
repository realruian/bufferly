import Foundation

struct ClipItem: Identifiable, Hashable {
    let id: UUID
    let kind: ClipKind
    let title: String
    /// 用户为固定内容设置的名称；nil 时继续使用自动生成标题。
    var customName: String?
    let preview: String
    let source: String
    /// 来源 App 的 bundle identifier，用于在卡片上显示来源 App 图标；未知来源为 nil。
    /// 可变：支持对旧数据回填。
    var sourceBundleID: String?
    /// 文本型：原始文本；附件型（图片/文件/富文本）：去重用的稳定键（哈希 / 文件路径 / 纯文本兜底）。
    let content: String
    /// 附件型的 blob 文件名（位于 blobs 目录），图片字节 / RTF 数据等存于此；文本型为 nil。
    let attachmentFilename: String?
    /// 回写剪贴板时要用的 pasteboard 类型（如 public.png / public.rtf / public.file-url）；文本型为 nil。
    let attachmentUTI: String?
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    /// 固定内容所属的单层分组；nil 表示未分组。
    var pinGroupID: UUID?
    var isSensitive: Bool

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        title: String,
        customName: String? = nil,
        preview: String,
        source: String,
        sourceBundleID: String? = nil,
        content: String,
        attachmentFilename: String? = nil,
        attachmentUTI: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        pinGroupID: UUID? = nil,
        isSensitive: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.customName = customName
        self.preview = preview
        self.source = source
        self.sourceBundleID = sourceBundleID
        self.content = content
        self.attachmentFilename = attachmentFilename
        self.attachmentUTI = attachmentUTI
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.pinGroupID = pinGroupID
        self.isSensitive = isSensitive
    }

    var displayTitle: String {
        customName ?? title
    }

    var relativeTime: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(updatedAt)))

        if elapsed < 60 {
            return "刚刚"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes) 分钟"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时"
        }

        let days = hours / 24
        if days == 1 {
            return "昨天"
        }

        return "\(days) 天"
    }
}
