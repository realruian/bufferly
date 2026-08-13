import Foundation

/// 二进制 / 大附件（图片字节、RTF 数据）不进 SQLite 主库，而是以独立文件存到
/// `Application Support/PastePop/blobs/`，数据库只保存文件名引用。保持主库小、读写快。
enum ClipBlobStore {
    static func blobsDirectory() throws -> URL {
        let directory = try AppDataLocation.directoryURL()
            .appendingPathComponent("blobs", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(for filename: String) -> URL? {
        (try? blobsDirectory())?.appendingPathComponent(filename, isDirectory: false)
    }

    @discardableResult
    static func write(_ data: Data, filename: String) -> Bool {
        guard let fileURL = url(for: filename) else {
            return false
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            AppLogger.storage.error("写入附件失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func read(filename: String) -> Data? {
        guard let fileURL = url(for: filename) else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    static func size(filename: String) -> Int64 {
        guard
            let fileURL = url(for: filename),
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return 0
        }
        return Int64(fileSize)
    }

    static func delete(filename: String) {
        guard let fileURL = url(for: filename) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func deleteOrphans(keeping activeFilenames: Set<String>) {
        guard let directory = try? blobsDirectory() else {
            return
        }

        guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        for filename in filenames where !activeFilenames.contains(filename) {
            delete(filename: filename)
        }
    }
}
