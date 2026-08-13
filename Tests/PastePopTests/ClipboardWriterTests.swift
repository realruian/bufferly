import AppKit
import Foundation
import Testing
@testable import PastePop

@Suite("ClipboardWriter")
struct ClipboardWriterTests {
    @Test("普通模式写回文本、图片和富文本")
    @MainActor
    func writesOriginalRepresentations() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastePopTests.\(UUID().uuidString)"))
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let richTextData = Data("{\\rtf1 test}".utf8)
        let attachments = [
            "image.png": imageData,
            "content.rtf": richTextData,
        ]
        let writer = ClipboardWriter(
            pasteboard: pasteboard,
            readAttachment: { attachments[$0] }
        )

        let text = makeClip(kind: .text, content: "普通文本", filename: nil)
        #expect(writer.write(text, mode: .original))
        #expect(pasteboard.string(forType: .string) == "普通文本")

        let image = makeClip(kind: .image, content: "image:hash", filename: "image.png")
        #expect(writer.write(image, mode: .original))
        #expect(pasteboard.data(forType: .png) == imageData)

        let richText = makeClip(kind: .richText, content: "测试正文", filename: "content.rtf")
        #expect(writer.write(richText, mode: .original))
        #expect(pasteboard.data(forType: .rtf) == richTextData)
        #expect(pasteboard.string(forType: .string) == "测试正文")
    }

    @Test("文件按 file URL 写回剪贴板")
    @MainActor
    func writesFileURLs() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastePopTests.\(UUID().uuidString)"))
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("PastePop 测试.txt")
        let clip = makeClip(kind: .file, content: fileURL.path, filename: nil)

        #expect(writer.write(clip, mode: .original))
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        #expect(urls == [fileURL])
    }

    @Test("纯文本模式不回写附件格式")
    @MainActor
    func writesPlainTextOnly() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastePopTests.\(UUID().uuidString)"))
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let richText = makeClip(kind: .richText, content: "纯文本", filename: "missing.rtf")

        #expect(writer.write(richText, mode: .plainText))
        #expect(pasteboard.string(forType: .string) == "纯文本")
        #expect(pasteboard.data(forType: .rtf) == nil)
    }

    @Test("敏感占位和图片不能以纯文本模式写回")
    @MainActor
    func rejectsUnavailableContent() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastePopTests.\(UUID().uuidString)"))
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let sensitive = ClipClassifier.makeMaskedSecret()
        let image = makeClip(kind: .image, content: "image:hash", filename: "missing.png")

        #expect(!writer.write(sensitive, mode: .original))
        #expect(!writer.write(image, mode: .plainText))
    }

    private func makeClip(kind: ClipKind, content: String, filename: String?) -> ClipItem {
        ClipItem(
            kind: kind,
            title: "测试",
            preview: content,
            source: "Tests",
            content: content,
            attachmentFilename: filename
        )
    }
}
