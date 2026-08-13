import Foundation

/// 敏感内容检测：token / API key / 私钥 / 密码 / `.env` 值 / 连接串密码 / 验证码等。
/// 命中后由上层决定是否脱敏或不入库。规则偏保守：宁可漏判，也尽量不误判
/// 普通 URL、文件路径、commit hash、包名、代码标识符等开发者高频复制的内容。
enum SensitiveContentFilter {
    private static let scanWindowLength = 65_536
    private static let scanWindowOverlap = 1_024

    static func isSensitive(_ rawText: String) -> Bool {
        let content = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            return false
        }

        // 私钥块特征极强且检查便宜，放在长度上限之前，避免长文件里的私钥漏判。
        if isPrivateKeyBlock(content) {
            return true
        }

        guard content.utf16.count > scanWindowLength else {
            return isSensitiveWithinScanWindow(content)
        }

        // 超长文本分窗扫描，避免把“超过上限”误当成安全；窗口重叠可覆盖跨边界的凭证。
        let nsContent = content as NSString
        let step = scanWindowLength - scanWindowOverlap
        var location = 0

        while location < nsContent.length {
            let length = min(scanWindowLength, nsContent.length - location)
            if isSensitiveWithinScanWindow(nsContent.substring(with: NSRange(location: location, length: length))) {
                return true
            }
            location += step
        }

        return false
    }

    private static func isSensitiveWithinScanWindow(_ content: String) -> Bool {
        return isSingleSecretToken(content)
            || containsInlineSecretToken(content)
            || hasSensitiveAssignment(content)
            || hasURLWithEmbeddedPassword(content)
            || isVerificationCodeMessage(content)
            || isLikelyHighEntropyToken(content)
    }

    // MARK: - 已知服务密钥前缀

    /// 常见服务的密钥前缀。命中前缀本身不够，还要求密钥主体形态合理（见 `matchesKnownSecretPrefix`）。
    private static let secretPrefixes: [String] = [
        // OpenAI / Anthropic / OpenRouter 等 sk- 系
        "sk-",
        // Stripe
        "sk_live_", "sk_test_", "rk_live_", "rk_test_", "pk_live_", "whsec_",
        // GitHub
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",
        // GitLab
        "glpat-", "glrt-",
        // Slack
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "xoxs-", "xapp-",
        // AWS Access Key ID
        "AKIA", "ASIA", "ABIA", "ACCA",
        // Google API key / OAuth access token
        "AIza", "ya29.",
        // npm / PyPI
        "npm_", "pypi-",
        // Hugging Face / Replicate
        "hf_", "r8_",
        // Vercel（vercel_blob_rw_ 等带前缀 token）
        "vercel_",
        // DigitalOcean / Shopify / Square / SendGrid
        "dop_v1_", "doo_v1_", "shpat_", "shpss_", "sq0atp-", "sq0csp-", "SG.",
        // Docker / Sentry / Linear / Figma / HubSpot
        "dckr_pat_", "sntrys_", "lin_api_", "figd_", "pat-na1-", "pat-eu1-",
        // Groq / xAI / Perplexity
        "gsk_", "xai-", "pplx-"
    ]

    /// 这几家的 token 主体自带 `.` 分段；其余前缀命中但主体含点时按域名 / 文件名放行。
    private static let dotTolerantPrefixes: Set<String> = ["ya29.", "SG.", "sntrys_"]

    /// 单个无空白 token：已知前缀密钥或 JWT。
    private static func isSingleSecretToken(_ content: String) -> Bool {
        guard !content.contains(where: \.isWhitespace) else {
            return false
        }

        return matchesKnownSecretPrefix(content[...], minBodyCount: 8) || isJWTToken(content[...])
    }

    /// 多词内容（命令、代码、配置片段、`Authorization: Bearer ...`）里夹带的完整密钥。
    /// 密钥主体要求更长（16+），降低文档示例、教程片段被误判的概率。
    private static func containsInlineSecretToken(_ content: String) -> Bool {
        guard content.contains(where: \.isWhitespace) else {
            return false
        }

        let tokens = content.split { ch in
            ch.isWhitespace || "\"'`,;()[]{}<>=:&?!".contains(ch)
        }

        return tokens.contains { token in
            matchesKnownSecretPrefix(token, minBodyCount: 16) || isJWTToken(token, minCount: 60)
        }
    }

    private static func matchesKnownSecretPrefix(_ token: Substring, minBodyCount: Int) -> Bool {
        for prefix in secretPrefixes where token.hasPrefix(prefix) {
            let body = token.dropFirst(prefix.count)

            guard
                body.count >= minBodyCount,
                body.allSatisfy(isSecretBodyCharacter),
                body.contains(where: \.isNumber)
            else {
                continue
            }

            if body.contains("."), !dotTolerantPrefixes.contains(prefix) {
                continue
            }

            // 连续 4 个相同字符更像文档占位符（xxxx / 0000），随机密钥几乎不会出现。
            if hasRepeatedRun(body, length: 4) {
                continue
            }

            return true
        }

        return false
    }

    private static func isSecretBodyCharacter(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || "-_./+=".contains(ch))
    }

    // MARK: - 私钥 / JWT

    private static func isPrivateKeyBlock(_ content: String) -> Bool {
        content.contains("-----BEGIN") && content.contains("PRIVATE KEY")
    }

    /// JWT：`eyJ` 开头的三段 base64url。
    private static func isJWTToken(_ token: Substring, minCount: Int = 24) -> Bool {
        guard token.hasPrefix("eyJ"), token.count >= minCount else {
            return false
        }

        let segments = token.split(separator: ".")
        return segments.count == 3 && segments.allSatisfy { segment in
            segment.count >= 8 && segment.allSatisfy { ch in
                ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "=")
            }
        }
    }

    // MARK: - 键值赋值

    private static let sensitiveKeySegments: Set<String> = [
        "SECRET", "SECRETS", "PASSWORD", "PASSWD", "PASSPHRASE", "TOKEN",
        "APIKEY", "AUTH", "AUTHORIZATION", "CREDENTIAL", "CREDENTIALS"
    ]

    /// `X_KEY` 只在修饰词明确指向凭证时才算，避免 CACHE_KEY / SORT_KEY / PUBLIC_KEY 误伤。
    private static let keyQualifierSegments: Set<String> = [
        "API", "ACCESS", "PRIVATE", "SECRET", "SSH", "SIGNING", "ENCRYPTION", "MASTER", "SERVICE"
    ]

    private static let cjkSensitiveKeyWords = ["密码", "口令", "密钥", "凭证", "令牌"]

    /// `KEY=value` / `key: value` 风格赋值，键名带敏感语义且值像真实凭证。
    /// 覆盖多行 `.env`、shell export、JSON / YAML 行、代码字面量赋值和请求头。
    private static func hasSensitiveAssignment(_ content: String) -> Bool {
        for line in content.split(whereSeparator: \.isNewline) {
            // JSON / query string / shell 一行里可能有多组键值，按常见分隔符拆开逐段查。
            for chunk in line.split(whereSeparator: { ",;&".contains($0) }) where isSensitiveAssignmentChunk(chunk) {
                return true
            }
        }

        return false
    }

    private static func isSensitiveAssignmentChunk(_ chunk: Substring) -> Bool {
        guard let separator = findAssignmentSeparator(in: chunk) else {
            return false
        }

        guard keyLooksSensitive(chunk[..<separator.index]) else {
            return false
        }

        var valueText = chunk[chunk.index(after: separator.index)...]
            .trimmingCharacters(in: .whitespaces)

        // `Authorization: Bearer xxx` 之类，剥掉 scheme 直接看凭证本体。
        for scheme in ["Bearer ", "bearer ", "Basic ", "basic ", "token "] where valueText.hasPrefix(scheme) {
            valueText = String(valueText.dropFirst(scheme.count))
            break
        }

        guard let firstWord = valueText.split(whereSeparator: \.isWhitespace).first else {
            return false
        }

        let value = firstWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;)}]"))
        return valueLooksLikeCredential(value, requiresDigit: separator.requiresDigitValue)
    }

    /// 找 chunk 里第一个赋值分隔符。跳过 `==` / `!=` / `>=` 等比较运算与 `://`、时间戳里的冒号。
    /// 代码风格的 `key = value`（等号带空格）与 `key: value` 额外要求值里含数字，进一步压误判。
    private static func findAssignmentSeparator(
        in chunk: Substring
    ) -> (index: Substring.Index, requiresDigitValue: Bool)? {
        var previous: Character?
        var index = chunk.startIndex

        while index < chunk.endIndex {
            let ch = chunk[index]
            let nextIndex = chunk.index(after: index)
            let next: Character? = nextIndex < chunk.endIndex ? chunk[nextIndex] : nil

            defer {
                previous = ch
                index = nextIndex
            }

            switch ch {
            case "=":
                let isComparison = next == "=" || previous.map { "!<>+-*/%&|^=~".contains($0) } == true
                if isComparison {
                    continue
                }
                return (index, previous?.isWhitespace == true)

            case ":":
                // 只认后面跟空白或引号的冒号，排除 `://`、`::`、时间 `12:34`。
                if let next, next.isWhitespace || next == "\"" || next == "'" {
                    return (index, true)
                }

            case "：":
                return (index, true)

            default:
                break
            }
        }

        return nil
    }

    private static func keyLooksSensitive(_ keyPart: Substring) -> Bool {
        if cjkSensitiveKeyWords.contains(where: keyPart.contains) {
            return true
        }

        // 整段精确匹配，避免 AUTHOR / TOKENIZER / MAX_TOKENS 这类子串误伤。
        let segments = keyPart.uppercased().split { !($0.isLetter || $0.isNumber) }

        if segments.contains(where: { sensitiveKeySegments.contains(String($0)) }) {
            return true
        }

        for i in segments.indices.dropLast() where segments[i + 1] == "KEY" {
            if keyQualifierSegments.contains(String(segments[i])) {
                return true
            }
        }

        return false
    }

    private static let valuePlaceholderWords: Set<String> = [
        "true", "false", "null", "none", "nil", "undefined", "yes", "no",
        "changeme", "change_me", "password", "example", "secret", "redacted",
        "placeholder", "hidden", "masked", "sample", "string", "value",
        "required", "optional"
    ]

    private static func valueLooksLikeCredential(_ value: String, requiresDigit: Bool) -> Bool {
        guard value.count >= 6 else {
            return false
        }

        if requiresDigit, !value.contains(where: \.isNumber) {
            return false
        }

        // 插值 / 占位符 / 表达式开头：`$VAR`、`${{ ... }}`、`<your-key>`、`%VAR%` 等。
        if let first = value.first, "$<{%*(".contains(first) {
            return false
        }

        // 真实凭证是 ASCII 单词；括号意味着函数调用、下标等代码表达式。
        guard value.allSatisfy({ $0.isASCII && !"()[]{}<>".contains($0) }) else {
            return false
        }

        // `process.env.API_KEY` 这类属性链是代码，不是凭证字面量。
        if isIdentifierPath(value) {
            return false
        }

        if valuePlaceholderWords.contains(value.lowercased()) {
            return false
        }

        // `xxxxxx` / `000000` 之类占位。
        if hasRepeatedRun(value[...], length: 4) {
            return false
        }

        return true
    }

    private static func isIdentifierPath(_ value: String) -> Bool {
        let parts = value.split(separator: ".")

        guard parts.count >= 2 else {
            return false
        }

        return parts.allSatisfy { part in
            guard let first = part.first, first.isLetter || first == "_" else {
                return false
            }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }

    // MARK: - 连接串密码

    /// `scheme://user:password@host` 形式的连接串（数据库 URL、带凭证的 registry 等）。
    private static func hasURLWithEmbeddedPassword(_ content: String) -> Bool {
        var searchStart = content.startIndex

        while let schemeRange = content.range(of: "://", range: searchStart..<content.endIndex) {
            searchStart = schemeRange.upperBound

            let authority = content[schemeRange.upperBound...].prefix { !$0.isWhitespace && $0 != "/" }

            guard
                let atIndex = authority.lastIndex(of: "@"),
                let colonIndex = authority[..<atIndex].firstIndex(of: ":")
            else {
                continue
            }

            let user = authority[..<colonIndex]
            let password = authority[authority.index(after: colonIndex)..<atIndex]

            guard !user.isEmpty, password.count >= 4 else {
                continue
            }

            if let first = password.first, "$<{%".contains(first) {
                continue
            }

            // 文档模板常用占位（postgres://USER:PASSWORD@HOST 等）不算真实凭证。
            let lowered = password.lowercased()
            let placeholderFragments = ["password", "passwd", "secret", "example", "changeme", "xxxx", "****", "your"]
            if placeholderFragments.contains(where: lowered.contains) {
                continue
            }

            return true
        }

        return false
    }

    // MARK: - 验证码消息

    private static let cjkCodeKeywords = ["验证码", "驗證碼", "校验码", "动态口令", "动态密码", "一次性密码"]

    private static let asciiCodeKeywordPattern =
        #"\b(otp|2fa)\b|verification code|verify code|one[- ]time (password|passcode|code)|security code|login code|auth code|sms code"#

    /// 短信 / 邮件验证码：出现验证码关键词，且带 4-8 位独立数字。
    private static func isVerificationCodeMessage(_ content: String) -> Bool {
        guard content.count <= 400 else {
            return false
        }

        let hasKeyword = cjkCodeKeywords.contains(where: content.contains)
            || content.lowercased().range(of: asciiCodeKeywordPattern, options: .regularExpression) != nil

        guard hasKeyword else {
            return false
        }

        return content.range(
            of: #"(?<![0-9])[0-9]{4,8}(?![0-9])"#,
            options: .regularExpression
        ) != nil
    }

    // MARK: - 高熵 token 兜底

    private static let tokenScalars = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_+/=.")

    /// 常见文件扩展名结尾的单 token 按文件名放行。
    private static let filenameExtensionPattern =
        #"(?i)\.(tar\.gz|tar\.bz2|tar\.xz|tgz|zip|rar|7z|dmg|pkg|app|whl|jar|gem|crate|pdf|docx?|xlsx?|pptx?|txt|md|rtf|csv|tsv|log|json|ya?ml|toml|ini|xml|plist|lock|swift|[jt]sx?|mjs|cjs|py|rb|go|rs|java|kt|kts|c|h|cc|cpp|hpp|m|mm|cs|php|pl|sh|zsh|bash|fish|sql|html?|css|scss|less|png|jpe?g|gif|webp|heic|avif|svg|ico|icns|mp[34]|mov|m4[av]|wav|flac|ttf|otf|woff2?|eot)$"#

    /// 单段无空白、长且形似随机的字符串，疑似无前缀凭证（保守兜底）。
    private static func isLikelyHighEntropyToken(_ content: String) -> Bool {
        guard
            !content.contains(where: \.isWhitespace),
            (24...256).contains(content.count),
            content.unicodeScalars.allSatisfy(tokenScalars.contains),
            content.contains(where: \.isUppercase),
            content.contains(where: \.isLowercase),
            content.contains(where: \.isNumber)
        else {
            return false
        }

        // URL / 文件路径：分隔性 `/` 且没有 base64 特征字符（+ =）时按路径放行。
        if content.contains("://") {
            return false
        }
        if content.contains("/"), !content.contains("+"), !content.contains("=") {
            return false
        }

        if content.range(of: filenameExtensionPattern, options: .regularExpression) != nil {
            return false
        }

        // 版本号 / 包名 / 文件名式标识符：按分隔符拆开后全是纯字母段、纯数字段或短段。
        let segments = content.split { "-_./".contains($0) }
        if
            segments.count >= 2,
            segments.allSatisfy({ $0.count <= 4 || $0.allSatisfy(\.isLetter) || $0.allSatisfy(\.isNumber) })
        {
            return false
        }

        // 长驼峰单词（≥12 连续字母）更像代码符号而不是随机凭证。
        if longestLetterRun(in: content) >= 12 {
            return false
        }

        return true
    }

    // MARK: - 通用小工具

    /// 是否存在长度 ≥ `length` 的连续相同字符。
    private static func hasRepeatedRun(_ text: Substring, length: Int) -> Bool {
        var runLength = 1
        var previous: Character?

        for ch in text {
            if ch == previous {
                runLength += 1
                if runLength >= length {
                    return true
                }
            } else {
                runLength = 1
                previous = ch
            }
        }

        return false
    }

    private static func longestLetterRun(in content: String) -> Int {
        var best = 0
        var current = 0

        for ch in content {
            if ch.isLetter {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }

        return best
    }
}
