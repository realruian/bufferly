import Foundation

enum AppDataLocation {
    private static let directoryName = "PastePop"
    private static let databaseName = "pastepop.sqlite"

    static func directoryURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    static func databaseURL() throws -> URL {
        let directoryURL = try directoryURL()
        return directoryURL.appendingPathComponent(databaseName)
    }
}
