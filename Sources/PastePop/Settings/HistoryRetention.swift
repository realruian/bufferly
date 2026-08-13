import Foundation

enum HistoryRetention: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case thirtyDays
    case forever

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneDay:
            "1 天"
        case .sevenDays:
            "7 天"
        case .thirtyDays:
            "30 天"
        case .forever:
            "永久"
        }
    }

    var summary: String {
        switch self {
        case .oneDay:
            "保留最近 1 天"
        case .sevenDays:
            "保留最近 7 天"
        case .thirtyDays:
            "保留最近 30 天"
        case .forever:
            "不按时间自动删除"
        }
    }

    var days: Int? {
        switch self {
        case .oneDay:
            1
        case .sevenDays:
            7
        case .thirtyDays:
            30
        case .forever:
            nil
        }
    }
}
