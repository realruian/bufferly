import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "PastePop"

    static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
}
