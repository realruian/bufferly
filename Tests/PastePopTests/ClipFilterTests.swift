import Foundation
import Testing
@testable import PastePop

@Suite("ClipFilter")
struct ClipFilterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("类型、来源和时间可以组合筛选")
    func combinesAllDimensions() {
        let matching = makeClip(kind: .url, source: "Safari", age: 2 * 24 * 60 * 60)
        let wrongType = makeClip(kind: .text, source: "Safari", age: 2 * 24 * 60 * 60)
        let wrongSource = makeClip(kind: .url, source: "Mail", age: 2 * 24 * 60 * 60)
        let tooOld = makeClip(kind: .url, source: "Safari", age: 10 * 24 * 60 * 60)
        let filter = ClipFilter(typeName: "链接", source: "Safari", time: .sevenDays)

        #expect(filter.matches(matching, now: now))
        #expect(!filter.matches(wrongType, now: now))
        #expect(!filter.matches(wrongSource, now: now))
        #expect(!filter.matches(tooOld, now: now))
        #expect(filter.activeCount == 3)
    }

    @Test("全部条件不限制结果")
    func allConditionsMatchEverything() {
        let clip = makeClip(kind: .image, source: "预览", age: 365 * 24 * 60 * 60)
        #expect(ClipFilter().matches(clip, now: now))
        #expect(!ClipFilter().isActive)
    }

    @Test("筛选标签可以应用、替换和移除")
    func tokenEditing() {
        var filter = ClipFilter()
        filter.apply(.type("链接"))
        filter.apply(.source("Safari"))
        filter.apply(.time(.yesterday))

        #expect(filter.tokens == [.type("链接"), .source("Safari"), .time(.yesterday)])

        filter.apply(.type("图片"))
        #expect(filter.typeName == "图片")
        #expect(filter.activeCount == 3)

        filter.remove(.source("Safari"))
        #expect(filter.source == nil)
        #expect(filter.activeCount == 2)
    }

    @Test("昨天和本周使用自然日边界")
    func naturalDateRanges() {
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = startOfToday.addingTimeInterval(-12 * 60 * 60)
        let twoDaysAgo = startOfToday.addingTimeInterval(-36 * 60 * 60)

        #expect(ClipTimeFilter.yesterday.includes(yesterday, now: now, calendar: calendar))
        #expect(!ClipTimeFilter.yesterday.includes(twoDaysAgo, now: now, calendar: calendar))
        #expect(!ClipTimeFilter.yesterday.includes(now, now: now, calendar: calendar))
        #expect(ClipTimeFilter.thisWeek.includes(now, now: now, calendar: calendar))
    }

    @Test("搜索词会混合推荐类型、来源和时间")
    func mixedSuggestions() {
        let lSuggestions = ClipFilterSuggestionEngine.suggestions(
            query: "l",
            typeNames: ["链接", "图片"],
            sources: ["Linear", "Safari"],
            activeFilter: ClipFilter(),
            limit: 10
        )

        #expect(lSuggestions.contains(.type("链接")))
        #expect(lSuggestions.contains(.source("Linear")))
        #expect(lSuggestions.contains(.time(.sevenDays)))

        let activeFilter = ClipFilter(typeName: "链接")
        let filteredSuggestions = ClipFilterSuggestionEngine.suggestions(
            query: "link",
            typeNames: ["链接"],
            sources: [],
            activeFilter: activeFilter
        )
        #expect(!filteredSuggestions.contains(.type("链接")))
    }

    private func makeClip(kind: ClipKind, source: String, age: TimeInterval) -> ClipItem {
        ClipItem(
            kind: kind,
            title: "测试",
            preview: "测试",
            source: source,
            content: "测试-\(kind.rawValue)-\(source)-\(age)",
            updatedAt: now.addingTimeInterval(-age)
        )
    }
}
