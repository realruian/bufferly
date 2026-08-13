import Foundation

enum ClipTimeFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case thisWeek
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            "全部时间"
        case .today:
            "今天"
        case .yesterday:
            "昨天"
        case .thisWeek:
            "本周"
        case .sevenDays:
            "最近 7 天"
        case .thirtyDays:
            "最近 30 天"
        }
    }

    func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return date >= calendar.startOfDay(for: now)
        case .yesterday:
            let today = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? .distantPast
            return date >= yesterday && date < today
        case .thisWeek:
            return date >= (calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast)
        case .sevenDays:
            return date >= (calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast)
        case .thirtyDays:
            return date >= (calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast)
        }
    }
}

struct ClipFilter: Equatable {
    var typeName: String?
    var source: String?
    var time: ClipTimeFilter = .all

    var activeCount: Int {
        (typeName == nil ? 0 : 1)
            + (source == nil ? 0 : 1)
            + (time == .all ? 0 : 1)
    }

    var isActive: Bool {
        activeCount > 0
    }

    var tokens: [ClipFilterToken] {
        var result: [ClipFilterToken] = []
        if let typeName {
            result.append(.type(typeName))
        }
        if let source {
            result.append(.source(source))
        }
        if time != .all {
            result.append(.time(time))
        }
        return result
    }

    mutating func apply(_ token: ClipFilterToken) {
        switch token {
        case .type(let typeName):
            self.typeName = typeName
        case .source(let source):
            self.source = source
        case .time(let time):
            self.time = time
        }
    }

    mutating func remove(_ token: ClipFilterToken) {
        switch token {
        case .type(let typeName) where self.typeName == typeName:
            self.typeName = nil
        case .source(let source) where self.source == source:
            self.source = nil
        case .time(let time) where self.time == time:
            self.time = .all
        default:
            break
        }
    }

    func matches(_ clip: ClipItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let typeName, clip.kind.displayName != typeName {
            return false
        }

        if let source, clip.source != source {
            return false
        }

        return time.includes(clip.updatedAt, now: now, calendar: calendar)
    }
}

enum ClipFilterToken: Hashable, Identifiable {
    case type(String)
    case source(String)
    case time(ClipTimeFilter)

    var id: String {
        switch self {
        case .type(let value):
            "type:\(value)"
        case .source(let value):
            "source:\(value)"
        case .time(let value):
            "time:\(value.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .type(let value), .source(let value):
            value
        case .time(let value):
            value.displayName
        }
    }

    fileprivate var categoryOrder: Int {
        switch self {
        case .type:
            0
        case .source:
            1
        case .time:
            2
        }
    }

    fileprivate var searchTerms: [String] {
        switch self {
        case .type(let value):
            [value] + Self.typeAliases[value, default: []]
        case .source(let value):
            [value]
        case .time(let value):
            [value.displayName] + Self.timeAliases[value, default: []]
        }
    }

    private static let typeAliases: [String: [String]] = [
        "文字": ["text"],
        "链接": ["link", "url"],
        "邮箱": ["email", "mail"],
        "图片": ["image", "photo"],
        "文件": ["file"],
        "敏感内容": ["secret", "password"],
        "验证码": ["code", "verification"],
        "电话": ["phone"],
        "地址": ["address", "location"],
        "账号信息": ["account"],
    ]

    private static let timeAliases: [ClipTimeFilter: [String]] = [
        .today: ["today"],
        .yesterday: ["yesterday"],
        .thisWeek: ["this week", "week"],
        .sevenDays: ["last week", "7 days"],
        .thirtyDays: ["last month", "30 days", "month"],
    ]
}

enum ClipFilterSuggestionEngine {
    static func suggestions(
        query: String,
        typeNames: [String],
        sources: [String],
        activeFilter: ClipFilter,
        limit: Int = 5
    ) -> [ClipFilterToken] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let candidates = typeNames.map(ClipFilterToken.type)
            + sources.map(ClipFilterToken.source)
            + ClipTimeFilter.allCases.filter { $0 != .all }.map(ClipFilterToken.time)

        return candidates
            .filter { !activeFilter.tokens.contains($0) }
            .compactMap { token in
                bestScore(query: trimmed, for: token).map { (token, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.0.categoryOrder != rhs.0.categoryOrder {
                    return lhs.0.categoryOrder < rhs.0.categoryOrder
                }
                return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func bestScore(query: String, for token: ClipFilterToken) -> Int? {
        let normalizedQuery = query.lowercased()
        return token.searchTerms.compactMap { term -> Int? in
            let normalizedTerm = term.lowercased()
            if normalizedTerm == normalizedQuery {
                return 1_000
            }
            if normalizedTerm.hasPrefix(normalizedQuery) {
                return 700 - normalizedTerm.count
            }
            if let range = normalizedTerm.range(of: normalizedQuery) {
                return 500 - normalizedTerm.distance(from: normalizedTerm.startIndex, to: range.lowerBound)
            }
            return FuzzySearch.score(query: normalizedQuery, in: normalizedTerm).map { 100 + $0 }
        }.max()
    }
}
