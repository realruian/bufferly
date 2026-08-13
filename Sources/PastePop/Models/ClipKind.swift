import SwiftUI

/// 内容类型。`rawValue` 只作为数据库存储键，已有值不可改动；
/// 面向用户的名称一律使用 `displayName`。
enum ClipKind: String, CaseIterable, Identifiable {
    case text = "文本"
    case url = "URL"
    case json = "JSON"
    case command = "命令"
    case code = "代码"
    case email = "邮件"
    case image = "图片"
    case file = "文件"
    case richText = "富文本"
    case secret = "敏感"
    case verificationCode = "验证码"
    case phone = "电话"
    case address = "地址"
    case account = "账号信息"

    var id: String { rawValue }

    /// 普通用户能一眼懂的中文标签。开发者向类型（代码 / JSON / 命令 / 富文本）
    /// 不再作为主线标签展示，统一弱化为「文字」，仅保留等宽排版等高级呈现。
    var displayName: String {
        switch self {
        case .text, .json, .command, .code, .richText:
            "文字"
        case .url:
            "链接"
        case .email:
            "邮箱"
        case .image:
            "图片"
        case .file:
            "文件"
        case .secret:
            "敏感内容"
        case .verificationCode:
            "验证码"
        case .phone:
            "电话"
        case .address:
            "地址"
        case .account:
            "账号信息"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            "text.alignleft"
        case .url:
            "link"
        case .json:
            "curlybraces"
        case .command:
            "terminal"
        case .code:
            "chevron.left.forwardslash.chevron.right"
        case .email:
            "envelope"
        case .image:
            "photo"
        case .file:
            "doc"
        case .richText:
            "doc.richtext"
        case .secret:
            "lock"
        case .verificationCode:
            "ellipsis.rectangle"
        case .phone:
            "phone"
        case .address:
            "mappin.and.ellipse"
        case .account:
            "person.text.rectangle"
        }
    }

    var hugeIconName: String {
        switch self {
        case .text:
            "text-align-left"
        case .url:
            "link-01"
        case .json:
            "third-bracket"
        case .command:
            "command-line"
        case .code:
            "code"
        case .email:
            "mail-01"
        case .image:
            "image-02"
        case .file:
            "file-empty-02"
        case .richText:
            "file-02"
        case .secret:
            "square-lock-01"
        case .verificationCode:
            "lock-password"
        case .phone:
            "call-02"
        case .address:
            "location-01"
        case .account:
            "user-account"
        }
    }

    /// 二进制 / 附件型：内容不是纯文本，正文存到 blob，卡片按各自方式渲染。
    var isAttachment: Bool {
        self == .image || self == .file || self == .richText
    }

    var tint: Color {
        switch self {
        case .secret:
            Color(red: 0.439, green: 0.251, blue: 0.373)
        default:
            .secondary
        }
    }

    /// 卡片彩色头部使用的颜色，按内容类型区分。
    /// 颜色只帮助扫读类型，不承担选中态。
    /// 开发者向类型统一用「文字」蓝，不再单独占用颜色。
    var accent: Color {
        switch self {
        case .text, .json, .command, .code, .richText:
            Color(red: 0.0, green: 0.533, blue: 1.0)
        case .url:
            Color(red: 0.204, green: 0.780, blue: 0.345)
        case .email:
            .pink
        case .image:
            Color(red: 1.0, green: 0.220, blue: 0.235)
        case .file:
            Color(red: 1.0, green: 0.584, blue: 0.0)
        case .secret:
            Color(red: 0.439, green: 0.251, blue: 0.373)
        case .verificationCode:
            .purple
        case .phone:
            .teal
        case .address:
            .indigo
        case .account:
            Color(red: 0.34, green: 0.38, blue: 0.46)
        }
    }
}
