import CryptoKit
import Foundation

enum ClipClassifier {
    static func makeClip(from rawText: String, source: String = "剪贴板", sourceBundleID: String? = nil) -> ClipItem? {
        let content = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            return nil
        }

        let kind = detectKind(for: content)

        return ClipItem(
            kind: kind,
            title: makeTitle(for: content, kind: kind),
            preview: makePreview(for: content),
            source: source,
            sourceBundleID: sourceBundleID,
            content: content
        )
    }

    /// 图片：content 用图片字节的哈希作去重键，PNG 字节存到 blob（文件名由调用方写入）。
    static func makeImageClip(png: Data, pixelSize: CGSize?, source: String = "剪贴板", sourceBundleID: String? = nil) -> ClipItem {
        let id = UUID()
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()

        let sizeText: String
        if let pixelSize, pixelSize.width > 0, pixelSize.height > 0 {
            sizeText = "图片 · \(Int(pixelSize.width))×\(Int(pixelSize.height))"
        } else {
            sizeText = "图片"
        }

        return ClipItem(
            id: id,
            kind: .image,
            title: sizeText,
            preview: sizeText,
            source: source,
            sourceBundleID: sourceBundleID,
            content: "image:\(hash)",
            attachmentFilename: "\(id.uuidString).png",
            attachmentUTI: "public.png"
        )
    }

    /// 文件：content 用文件路径（天然去重），不写 blob，回写时按 file-url 还原。
    static func makeFileClip(urls: [URL], source: String = "剪贴板", sourceBundleID: String? = nil) -> ClipItem? {
        guard !urls.isEmpty else {
            return nil
        }

        let paths = urls.map(\.path).joined(separator: "\n")
        let firstName = urls[0].lastPathComponent
        let title = urls.count > 1 ? "\(firstName) 等 \(urls.count) 个" : firstName

        return ClipItem(
            kind: .file,
            title: title,
            preview: paths,
            source: source,
            sourceBundleID: sourceBundleID,
            content: paths,
            attachmentUTI: "public.file-url"
        )
    }

    /// 富文本：content 用纯文本兜底（去重 + 纯文本粘贴），RTF 数据存到 blob。
    static func makeRichTextClip(rtf: Data, plain: String, source: String = "剪贴板", sourceBundleID: String? = nil) -> ClipItem? {
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let id = UUID()
        return ClipItem(
            id: id,
            kind: .richText,
            title: makeTitle(for: trimmed, kind: .richText),
            preview: makePreview(for: trimmed),
            source: source,
            sourceBundleID: sourceBundleID,
            content: trimmed,
            attachmentFilename: "\(id.uuidString).rtf",
            attachmentUTI: "public.rtf"
        )
    }

    /// 命中敏感规则时的脱敏占位：不保存明文（content 为空），仅留一个 lock 卡片。
    static func makeMaskedSecret(source: String = "剪贴板", sourceBundleID: String? = nil) -> ClipItem {
        ClipItem(
            kind: .secret,
            title: "敏感内容已隐藏",
            preview: "敏感内容已隐藏",
            source: source,
            sourceBundleID: sourceBundleID,
            content: "",
            isSensitive: true
        )
    }

    /// 类型识别：全部本地、轻量、可解释的规则，不依赖云端。
    /// 敏感内容的判定在上游（`SensitiveContentFilter`）先行，优先级最高。
    private static func detectKind(for content: String) -> ClipKind {
        // 长日志 / 文档不做正则与 JSON 全量解析；这类内容按普通文字展示即可。
        guard content.utf8.count <= 512 * 1_024 else {
            return .text
        }

        if isVerificationCode(content) {
            return .verificationCode
        }

        if isEmail(content) {
            return .email
        }

        if isURL(content) {
            return .url
        }

        if isBankCardNumber(content) {
            return .account
        }

        if isPhoneNumber(content) {
            return .phone
        }

        // 开发者向类型仍然识别（保留等宽预览等高级呈现），但展示上弱化为「文字」。
        if isJSON(content) {
            return .json
        }

        if isShellCommand(content) {
            return .command
        }

        if isCodeLike(content) {
            return .code
        }

        if isAddress(content) {
            return .address
        }

        if isAccountInfo(content) {
            return .account
        }

        return .text
    }

    private static func makeTitle(for content: String, kind: ClipKind) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine, !firstLine.isEmpty else {
            return kind.displayName
        }

        if firstLine.count <= 48 {
            return firstLine
        }

        return String(firstLine.prefix(45)) + "..."
    }

    private static func makePreview(for content: String) -> String {
        // 只生成卡片会显示的前 180 个字符，避免为了短预览复制整份长文本。
        var compact = ""
        compact.reserveCapacity(181)
        var hasStarted = false
        var pendingLineSeparator = false
        var hasMore = false

        for character in content {
            if character.isNewline {
                if hasStarted {
                    pendingLineSeparator = true
                }
                continue
            }

            if !hasStarted, character.isWhitespace {
                continue
            }

            if pendingLineSeparator {
                compact.append(" ")
                pendingLineSeparator = false
            }

            compact.append(character)
            hasStarted = true
            if compact.count > 180 {
                hasMore = true
                break
            }
        }

        compact = compact.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasMore ? String(compact.prefix(177)) + "..." : compact
    }

    private static func isURL(_ content: String) -> Bool {
        guard content.count < 2_048 else {
            return false
        }

        if let url = URL(string: content), url.scheme != nil, url.host != nil {
            return true
        }

        return content.hasPrefix("www.")
            || content.hasPrefix("github.com/")
            || content.hasPrefix("developer.apple.com/")
    }

    private static func isEmail(_ content: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return content.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isJSON(_ content: String) -> Bool {
        guard let first = content.first, first == "{" || first == "[" else {
            return false
        }

        guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) else {
            return false
        }

        return JSONSerialization.isValidJSONObject(object)
    }

    private static func isShellCommand(_ content: String) -> Bool {
        let commandPrefixes = [
            "git ", "npm ", "pnpm ", "yarn ", "swift ", "cargo ", "python ",
            "python3 ", "node ", "curl ", "cd ", "ls ", "mkdir ", "rm ", "grep ",
            "rg ", "docker ", "brew "
        ]

        return !content.contains("\n") && commandPrefixes.contains { content.hasPrefix($0) }
    }

    private static func isCodeLike(_ content: String) -> Bool {
        let markers = ["func ", "struct ", "class ", "enum ", "import ", "let ", "const ", "=>", "{", "};"]
        let markerCount = markers.filter { content.contains($0) }.count

        return content.contains("\n") && markerCount >= 2
    }

    // MARK: - 普通用户类型识别（本地、轻量、可解释）

    /// 验证码：纯 4-8 位数字（排除 19xx / 20xx 年份），
    /// 或短文本里带验证码关键词且含 4-8 位独立数字码。
    /// 带关键词的完整验证码短信默认已被敏感过滤脱敏，此分支主要服务单独复制的数字码
    /// 和关闭了敏感过滤的用户。
    private static func isVerificationCode(_ content: String) -> Bool {
        if (4...8).contains(content.count), content.allSatisfy(\.isNumber) {
            let isYearLike = content.count == 4 && (content.hasPrefix("19") || content.hasPrefix("20"))
            return !isYearLike
        }

        guard content.count <= 400 else {
            return false
        }

        let keywords = ["验证码", "驗證碼", "校验码", "动态口令", "动态密码", "一次性密码", "verification code", "one-time pass"]
        let lower = content.lowercased()
        guard keywords.contains(where: lower.contains) else {
            return false
        }

        return content.range(of: #"(?<![0-9])[0-9]{4,8}(?![0-9])"#, options: .regularExpression) != nil
    }

    /// 电话：单行、7-15 位数字，只含数字与常见电话分隔符；排除日期。
    /// 纯 4-8 位数字在前面已按验证码处理。
    private static func isPhoneNumber(_ content: String) -> Bool {
        guard content.count <= 24, !content.contains(where: \.isNewline) else {
            return false
        }

        let digitCount = content.count(where: \.isNumber)
        guard (7...15).contains(digitCount) else {
            return false
        }

        guard content.allSatisfy({ $0.isNumber || "+-() ".contains($0) }) else {
            return false
        }

        // 2026-07-07 / 07-07-2026 这类日期不是电话。
        let datePatterns = [#"^\d{4}-\d{1,2}-\d{1,2}$"#, #"^\d{1,2}-\d{1,2}-\d{4}$"#]
        if datePatterns.contains(where: { content.range(of: $0, options: .regularExpression) != nil }) {
            return false
        }

        return true
    }

    /// 银行卡号：13-19 位数字（允许空格 / 连字符分组）且通过 Luhn 校验。
    private static func isBankCardNumber(_ content: String) -> Bool {
        guard
            content.count <= 30,
            content.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" })
        else {
            return false
        }

        let digits = content.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else {
            return false
        }

        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }

        return sum % 10 == 0
    }

    /// 地址：中文地址形态（行政区划 + 街道要素 + 数字），
    /// 或系统 NSDataDetector 的本地地址识别覆盖大部分内容。
    private static func isAddress(_ content: String) -> Bool {
        let lineCount = content.split(whereSeparator: \.isNewline).count
        guard content.count <= 100, lineCount <= 3 else {
            return false
        }

        // 中文地址：省市区 → 路街号 的先后形态，且带门牌数字，避免"城市道路设计规范"这类普通词组。
        if
            content.count <= 60,
            content.contains(where: \.isNumber),
            content.range(
                of: #"(省|市|自治区|特别行政区|区|县|镇|乡|村).*(路|街|道|大道|巷|弄|号|栋|幢|座|单元|室)"#,
                options: .regularExpression
            ) != nil
        {
            return true
        }

        // 西文地址走系统识别（纯本地），要求匹配覆盖 ≥60% 内容。
        guard
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        else {
            return false
        }

        let length = (content as NSString).length
        let matches = detector.matches(in: content, range: NSRange(location: 0, length: length))
        let covered = matches.reduce(0) { $0 + $1.range.length }
        return covered * 10 >= length * 6
    }

    /// 账号信息：账号类关键词 + 键值分隔符 + 数字（银行卡号在 `isBankCardNumber` 单独判）。
    private static func isAccountInfo(_ content: String) -> Bool {
        guard content.count <= 300 else {
            return false
        }

        let keywords = ["账号", "帐号", "账户", "帐户", "用户名", "会员号", "卡号", "username"]
        let lower = content.lowercased()
        guard keywords.contains(where: lower.contains) else {
            return false
        }

        guard content.contains(":") || content.contains("：") else {
            return false
        }

        return content.contains(where: \.isNumber)
    }
}
