import AppKit
import Foundation

/// 把历史条目按原格式或纯文本写回系统剪贴板。
@MainActor
struct ClipboardWriter {
    enum Mode {
        case original
        case plainText
    }

    private let pasteboard: NSPasteboard
    private let readAttachment: (String) -> Data?

    init(
        pasteboard: NSPasteboard = .general,
        readAttachment: @escaping (String) -> Data? = { ClipBlobStore.read(filename: $0) }
    ) {
        self.pasteboard = pasteboard
        self.readAttachment = readAttachment
    }

    func write(_ clip: ClipItem, mode: Mode = .original) -> Bool {
        guard !clip.isSensitive else { return false }

        if mode == .plainText {
            return writePlainText(clip)
        }

        switch clip.kind {
        case .image:
            guard
                let filename = clip.attachmentFilename,
                let data = readAttachment(filename)
            else {
                return false
            }
            pasteboard.clearContents()
            return pasteboard.setData(data, forType: .png)

        case .richText:
            pasteboard.clearContents()
            let wroteRTF = clip.attachmentFilename
                .flatMap(readAttachment)
                .map { pasteboard.setData($0, forType: .rtf) }
                ?? false
            let wroteText = pasteboard.setString(clip.content, forType: .string)
            return wroteRTF || wroteText

        case .file:
            let urls = clip.content
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls as [NSURL])

        default:
            return writePlainText(clip)
        }
    }

    private func writePlainText(_ clip: ClipItem) -> Bool {
        guard clip.kind != .image else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(clip.content, forType: .string)
    }
}
