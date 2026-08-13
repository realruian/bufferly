import Testing
@testable import PastePop

@Suite("ClipClassifier")
struct ClipClassifierTests {
    private func kind(of content: String) -> ClipKind? {
        ClipClassifier.makeClip(from: content)?.kind
    }

    // MARK: - 新增普通用户类型

    @Test("纯数字验证码识别")
    func detectsBareVerificationCode() {
        #expect(kind(of: "482913") == .verificationCode)
        #expect(kind(of: "0731") == .verificationCode)
        // 19xx / 20xx 年份不按验证码
        #expect(kind(of: "2026") == .text)
        #expect(kind(of: "1999") == .text)
    }

    @Test("带关键词的验证码消息识别")
    func detectsVerificationMessage() {
        // 注：默认开启敏感过滤时这类消息会先被脱敏，此处验证分类器自身的行为
        #expect(kind(of: "您的验证码是 482913") == .verificationCode)
    }

    @Test("电话号码识别")
    func detectsPhoneNumbers() {
        #expect(kind(of: "13800138000") == .phone)
        #expect(kind(of: "+86 138 0013 8000") == .phone)
        #expect(kind(of: "(555) 123-4567") == .phone)
        // 日期 / 版本号不是电话
        #expect(kind(of: "2026-07-07") == .text)
        #expect(kind(of: "1.2.3") == .text)
    }

    @Test("地址识别")
    func detectsAddresses() {
        #expect(kind(of: "浙江省杭州市西湖区文三路 100 号") == .address)
        #expect(kind(of: "上海市浦东新区世纪大道 88 号 2 楼 201 室") == .address)
        // 含地名字样的普通词组不是地址
        #expect(kind(of: "城市道路设计规范") == .text)
    }

    @Test("账号信息识别")
    func detectsAccountInfo() {
        // Visa 测试卡号，Luhn 校验通过
        #expect(kind(of: "4111 1111 1111 1111") == .account)
        #expect(kind(of: "会员号：8801234567") == .account)
        // 只提到账号但没有具体信息的普通句子不算
        #expect(kind(of: "账号注销流程说明") == .text)
    }

    @Test("邮箱与链接识别不受影响")
    func keepsEmailAndURL() {
        #expect(kind(of: "foo@example.com") == .email)
        #expect(kind(of: "https://github.com/Innate-Labs/bufferly") == .url)
    }

    // MARK: - 开发者类型弱化为高级类型

    @Test("开发者类型仍被识别（保留等宽预览）")
    func stillDetectsDeveloperKinds() {
        #expect(kind(of: "{\"name\": \"pastepop\", \"count\": 3}") == .json)
        #expect(kind(of: "git status") == .command)
    }

    @Test("开发者类型标签统一展示为「文字」")
    func developerKindsDisplayAsText() {
        #expect(ClipKind.json.displayName == "文字")
        #expect(ClipKind.command.displayName == "文字")
        #expect(ClipKind.code.displayName == "文字")
        #expect(ClipKind.richText.displayName == "文字")
    }

    @Test("用户可见标签均为普通用户友好中文")
    func displayNamesAreUserFriendly() {
        #expect(ClipKind.text.displayName == "文字")
        #expect(ClipKind.url.displayName == "链接")
        #expect(ClipKind.email.displayName == "邮箱")
        #expect(ClipKind.image.displayName == "图片")
        #expect(ClipKind.file.displayName == "文件")
        #expect(ClipKind.secret.displayName == "敏感内容")
        #expect(ClipKind.verificationCode.displayName == "验证码")
        #expect(ClipKind.phone.displayName == "电话")
        #expect(ClipKind.address.displayName == "地址")
        #expect(ClipKind.account.displayName == "账号信息")
    }
}
