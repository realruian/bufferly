import Foundation
import Testing
@testable import PastePop

@Suite("ClipboardCapturePolicy")
struct ClipboardCapturePolicyTests {
    @Test("文本和富文本载荷有明确上限")
    func limitsTextPayloads() {
        let accepted = String(repeating: "a", count: ClipboardCapturePolicy.maximumTextBytes)
        let rejected = accepted + "a"

        #expect(ClipboardCapturePolicy.acceptsText(accepted))
        #expect(!ClipboardCapturePolicy.acceptsText(rejected))
        #expect(!ClipboardCapturePolicy.acceptsRichText(Data(), plainText: rejected))
    }

    @Test("图片同时受编码体积和像素数约束")
    func limitsImagePayloads() {
        let smallData = Data(repeating: 0, count: 32)
        let tooLargeData = Data(
            repeating: 0,
            count: ClipboardCapturePolicy.maximumImageOutputBytes + 1
        )

        #expect(ClipboardCapturePolicy.acceptsImage(data: smallData, pixelSize: CGSize(width: 4_000, height: 4_000)))
        #expect(!ClipboardCapturePolicy.acceptsImage(data: smallData, pixelSize: CGSize(width: 10_000, height: 10_000)))
        #expect(!ClipboardCapturePolicy.acceptsImage(data: tooLargeData, pixelSize: CGSize(width: 1, height: 1)))
    }
}
