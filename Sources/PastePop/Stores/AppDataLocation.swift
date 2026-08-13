import Foundation

enum AppDataLocation {
    private static let currentDirectoryName = "PastePop"
    private static let currentDatabaseName = "pastepop.sqlite"

    // 仅用于品牌改名后的本地数据迁移，避免用户丢失原有剪贴板历史。
    private static let legacyDirectoryName = "Bufferly"
    private static let legacyDatabaseName = "bufferly.sqlite"

    static func directoryURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let currentURL = applicationSupportURL
            .appendingPathComponent(currentDirectoryName, isDirectory: true)
        let legacyURL = applicationSupportURL
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: currentURL.path),
           fileManager.fileExists(atPath: legacyURL.path)
        {
            try fileManager.moveItem(at: legacyURL, to: currentURL)
        }

        try fileManager.createDirectory(at: currentURL, withIntermediateDirectories: true)
        return currentURL
    }

    static func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try directoryURL()
        let currentURL = directoryURL.appendingPathComponent(currentDatabaseName)
        let legacyURL = directoryURL.appendingPathComponent(legacyDatabaseName)

        if !fileManager.fileExists(atPath: currentURL.path),
           fileManager.fileExists(atPath: legacyURL.path)
        {
            try fileManager.moveItem(at: legacyURL, to: currentURL)
        }

        return currentURL
    }
}
