import Testing
@testable import PastePop

// MARK: - 样本
// 所有密钥均为格式正确的假样本，仅用于验证过滤规则，不对应任何真实凭证。

private enum SensitiveSamples {
    /// jwt.io 风格的假 JWT（三段 base64url）。
    static let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkJ1ZmZlcmx5In0."
        + "Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z"

    /// 已知服务的单 token。
    static let knownServiceTokens: [String] = [
        // OpenAI
        "sk-proj-Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3dEf6h",
        // Anthropic
        "sk-ant-api03-Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3dEf6hIj9kLm2n",
        // GitHub classic / fine-grained PAT
        "ghp_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3d",
        "github_pat_11ABCDE2Y0Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3dEf6hIj9kLm2nOp5qRs8t",
        // AWS Access Key ID（官方文档示例格式）
        "AKIAIOSFODNN7EXAMPLE",
        // Stripe secret key / webhook secret（拆开拼接，避免被 GitHub push protection 当成真密钥拦截）
        "sk_live_" + "4eC39HqLyjWDarjtT1zdp7dc",
        "whsec_Ab3dEf6hIj9kLm2nOp5qRs8tUv1w",
        // Vercel Blob token
        "vercel_blob_rw_Ab3dEf6hIj9kLm2n_Op5qRs8tUv1wXy4z",
        // npm
        "npm_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3d",
        // Hugging Face
        "hf_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z",
        // Slack bot token（拆开拼接，避免被 GitHub push protection 当成真密钥拦截）
        "xoxb-" + "1234567890-1234567890123-Ab3dEf6hIj9kLm2nOp5qRs8t",
        // Google API key
        "AIzaSyAb3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zA"
    ]

    /// JWT：单独复制、请求头、curl 命令。
    static let jwtSamples: [String] = [
        jwt,
        "Authorization: Bearer \(jwt)",
        "curl -H 'Authorization: Bearer \(jwt)' https://api.example.com/v1/me"
    ]

    static let privateKeys: [String] = [
        """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACBn4mVcQhargVYWa88UZUdSGJhK2mUnPqCS0Ln2GBP9dw
        -----END OPENSSH PRIVATE KEY-----
        """,
        "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA1234\n-----END RSA PRIVATE KEY-----"
    ]

    /// 多行 .env / YAML 配置块。
    static let configBlocks: [String] = [
        """
        # 服务配置
        OPENAI_API_KEY=sk-Ab3dEf6hIj9kLm2nOp5qRs8tUv1w
        DATABASE_URL=postgres://app:S3cureP4ss@db.internal:5432/app
        DEBUG=true
        """,
        """
        service:
          api_key: "sk-Ab3dEf6hIj9kLm2nOp5qRs8tUv1w"
          timeout: 30
        """
    ]

    /// password / token / api key 赋值（env、shell、代码、JSON、请求头、中文）。
    static let assignments: [String] = [
        "export GITHUB_TOKEN=ghp_Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb3d",
        "PASSWORD=SuperSecret9",
        "password = \"hunter22\"",
        "let apiKey = \"Ab3dEf6hIj9kXy4zLm2n\"",
        "\"api_key\": \"Ab3dEf6hIj9kLm2n\"",
        "{\"user\": \"alice\", \"password\": \"N8x2mPq9kQ\"}",
        "Authorization: Bearer Ab3dEf6hIj9kLm2nOp5qRs8tUv1w",
        "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY",
        "服务器密码：Xy9kQm2Pv8"
    ]

    /// 带密码的连接串。
    static let connectionStrings: [String] = [
        "postgres://pastepop:N8x2mPq9@db.internal:5432/pastepop",
        "redis://default:Xy7kQ2mP9r@cache.internal:6379"
    ]

    /// 验证码消息。
    static let verificationCodes: [String] = [
        "【PastePop】您的验证码是 482913，5 分钟内有效，请勿泄露。",
        "Your PastePop verification code is 314159. It expires in 10 minutes."
    ]

    /// 无前缀的高熵凭证（如 Vercel access token 形态）。
    static let opaqueTokens: [String] = [
        "kA9mB2nC8dE1fG7hJ4kL6mN3",
        "U2VjcmV0QmFzZTY0RGF0YTEyMzQ1Ng=="
    ]
}

/// 开发者高频复制的普通内容：不应被误判。
private enum BenignSamples {
    static let all: [String] = [
        // 普通 URL
        "https://github.com/Innate-Labs/bufferly/releases/latest",
        "https://developer.apple.com/design/human-interface-guidelines",
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "https://api.example.com/v1/items?page=2&limit=50",
        // 文件路径
        "/Users/foo/Documents/Report2024.pdf",
        "~/Library/Application Support/PastePop/pastepop.sqlite",
        "Sources/PastePop/Services/SensitiveContentFilter.swift",
        // commit hash / UUID
        "adbec72f3c9e14ab07d5566e2171624632a95a07",
        "git rebase -i adbec72",
        "550e8400-e29b-41d4-a716-446655440000",
        // 包名 / 版本 / 构建产物
        "@types/node",
        "react-dom@18.3.1",
        "SomePackage-1.2.3-py3-none-any.whl",
        // 命令与代码
        "swift build && swift run PastePop",
        "git commit -m 'fix: token parsing'",
        "let tokenizer = Tokenizer()",
        "const apiKey = process.env.OPENAI_API_KEY",
        "password = newPassword",
        "if password == storedPassword { return }",
        "getUserAccessToken2024Handler",
        // 配置里非敏感键值 / 占位符
        "MAX_TOKENS=4096",
        "AUTHOR=Jane Smith",
        "GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}",
        "{\"theme\": \"dark\", \"fontSize\": 14}",
        "Set-Cookie: theme=dark",
        // 提到关键词但没有真实凭证
        "验证码通道已切换到新的短信供应商",
        "密码强度要求：至少 8 位",
        "TODO: rotate the API key next sprint"
    ]
}

// MARK: - 用例

@Suite("SensitiveContentFilter")
struct SensitiveContentFilterTests {
    @Test("已知服务 token 判为敏感", arguments: SensitiveSamples.knownServiceTokens)
    func detectsKnownServiceTokens(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("JWT（单独 / 请求头 / 命令内）判为敏感", arguments: SensitiveSamples.jwtSamples)
    func detectsJWT(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("私钥块判为敏感", arguments: SensitiveSamples.privateKeys)
    func detectsPrivateKeys(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("多行 .env / YAML 配置判为敏感", arguments: SensitiveSamples.configBlocks)
    func detectsConfigBlocks(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("password / token / api key 赋值判为敏感", arguments: SensitiveSamples.assignments)
    func detectsAssignments(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("带密码的连接串判为敏感", arguments: SensitiveSamples.connectionStrings)
    func detectsConnectionStrings(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("验证码消息判为敏感", arguments: SensitiveSamples.verificationCodes)
    func detectsVerificationCodes(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("无前缀高熵凭证判为敏感", arguments: SensitiveSamples.opaqueTokens)
    func detectsOpaqueTokens(sample: String) {
        #expect(SensitiveContentFilter.isSensitive(sample))
    }

    @Test("普通 URL / 路径 / hash / 包名 / 代码不误判", arguments: BenignSamples.all)
    func allowsBenignContent(sample: String) {
        #expect(!SensitiveContentFilter.isSensitive(sample))
    }

    @Test("超长内容里的私钥仍能命中")
    func detectsPrivateKeyInLongContent() {
        let padding = String(repeating: "let x = 1\n", count: 10_000)
        let content = padding + SensitiveSamples.privateKeys[0]
        #expect(SensitiveContentFilter.isSensitive(content))
    }

    @Test("超长内容末尾的普通凭证仍能命中")
    func detectsAssignmentAfterScanWindow() {
        let padding = String(repeating: "ordinary clipboard text\n", count: 4_000)
        let content = padding + "\nPASSWORD=SuperSecret9"
        #expect(SensitiveContentFilter.isSensitive(content))
    }
}
