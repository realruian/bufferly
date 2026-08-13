import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 一次剪贴板捕获的载荷。按优先级区分：文件 > 图片 > 富文本 > 纯文本。
enum ClipboardCapture: Sendable {
    case text(String)
    case richText(rtf: Data, plain: String)
    case image(png: Data, pixelSize: CGSize?)
    case files([URL])
}

struct ClipboardCaptureContext: Sendable {
    let source: String
    let sourceBundleID: String?
}

/// 防止异常大的剪贴板载荷进入分类、图片解码与持久化流程。
enum ClipboardCapturePolicy {
    static let maximumTextBytes = 4 * 1_024 * 1_024
    static let maximumRichTextBytes = 16 * 1_024 * 1_024
    static let maximumImageInputBytes = 32 * 1_024 * 1_024
    static let maximumImageOutputBytes = 24 * 1_024 * 1_024
    static let maximumImagePixels = 40_000_000
    static let maximumFileCount = 1_000

    static func acceptsText(_ text: String) -> Bool {
        text.utf8.count <= maximumTextBytes
    }

    static func acceptsRichText(_ data: Data, plainText: String) -> Bool {
        data.count <= maximumRichTextBytes && acceptsText(plainText)
    }

    static func acceptsImage(data: Data, pixelSize: CGSize?) -> Bool {
        guard data.count <= maximumImageOutputBytes else { return false }
        guard let pixelSize else { return true }
        return pixelSize.width > 0
            && pixelSize.height > 0
            && pixelSize.width * pixelSize.height <= CGFloat(maximumImagePixels)
    }
}

@MainActor
final class ClipboardMonitor {
    private nonisolated(unsafe) let pasteboard: NSPasteboard
    private let captureContext: () -> ClipboardCaptureContext?
    private let onCapture: (ClipboardCapture, ClipboardCaptureContext) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var pendingReadTask: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general,
        captureContext: @escaping () -> ClipboardCaptureContext?,
        onCapture: @escaping (ClipboardCapture, ClipboardCaptureContext) -> Void
    ) {
        self.pasteboard = pasteboard
        self.captureContext = captureContext
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func syncToCurrentChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    /// 立即检查一次剪贴板（呼出面板时调用），消除轮询间隔导致的「最新一条还没进来」。
    func checkNow() {
        poll()
    }

    private func poll() {
        let changeCount = pasteboard.changeCount

        guard changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount

        // 暂停或来源 App 被排除时，不读取任何真实载荷；只消费 changeCount。
        guard let context = captureContext() else {
            pendingReadTask?.cancel()
            pendingReadTask = nil
            return
        }

        pendingReadTask?.cancel()
        pendingReadTask = Task { @MainActor in
            guard let capture = await readCapture(), !Task.isCancelled else {
                return
            }

            onCapture(capture, context)
        }
    }

    /// 按优先级读取剪贴板：文件 > 图片 > 富文本 > 纯文本。
    private func readCapture() async -> ClipboardCapture? {
        let snapshot = await inspectPasteboard()

        guard !snapshot.shouldSkipHistory else {
            return nil
        }

        // 1) 文件 URL（Finder 复制文件）。
        if
            snapshot.canContainFileURL,
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL],
            !urls.isEmpty,
            urls.count <= ClipboardCapturePolicy.maximumFileCount
        {
            return .files(urls)
        }

        // 2) 图片：优先 PNG，否则把 TIFF 转成 PNG 统一存储。
        if snapshot.canContainImage, let image = await readImage() {
            return image
        }

        // 3) 富文本（RTF）：连同纯文本兜底一起带上。
        if
            snapshot.canContainRichText,
            let rtf = pasteboard.data(forType: .rtf),
            let plain = pasteboard.string(forType: .string),
            !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            ClipboardCapturePolicy.acceptsRichText(rtf, plainText: plain)
        {
            return .richText(rtf: rtf, plain: plain)
        }

        // 4) 纯文本。
        if
            snapshot.canContainPlainText,
            let text = pasteboard.string(forType: .string),
            ClipboardCapturePolicy.acceptsText(text)
        {
            return .text(text)
        }

        return nil
    }

    /// 先读取 pasteboard 类型和系统可提供的元数据，再决定是否读取真实内容。
    /// macOS 15.4+ 的 metadata detection 不会触发“读取剪贴板内容”的系统提醒。
    private func inspectPasteboard() async -> PasteboardSnapshot {
        let metadata = try? await pasteboard.detectedMetadata(for: [\NSPasteboard.DetectedMetadata.contentType])
        return PasteboardSnapshot(
            types: Set(pasteboard.types ?? []),
            detectedContentType: metadata?.contentType
        )
    }

    private func readImage() async -> ClipboardCapture? {
        if
            let png = pasteboard.data(forType: .png),
            png.count <= ClipboardCapturePolicy.maximumImageInputBytes
        {
            return await Task.detached(priority: .utility) {
                Self.makeImageCapture(from: png, convertToPNG: false)
            }.value
        }

        guard
            let tiff = pasteboard.data(forType: .tiff),
            tiff.count <= ClipboardCapturePolicy.maximumImageInputBytes
        else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            Self.makeImageCapture(from: tiff, convertToPNG: true)
        }.value
    }

    private nonisolated static func makeImageCapture(
        from data: Data,
        convertToPNG: Bool
    ) -> ClipboardCapture? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }

        let pixelSize = CGSize(width: width.doubleValue, height: height.doubleValue)
        guard pixelSize.width * pixelSize.height <= CGFloat(ClipboardCapturePolicy.maximumImagePixels) else {
            return nil
        }

        let pngData: Data
        if convertToPNG {
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    output,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                )
            else {
                return nil
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            pngData = output as Data
        } else {
            pngData = data
        }

        guard ClipboardCapturePolicy.acceptsImage(data: pngData, pixelSize: pixelSize) else {
            return nil
        }
        return .image(png: pngData, pixelSize: pixelSize)
    }

    deinit {
        MainActor.assumeIsolated {
            pendingReadTask?.cancel()
            timer?.invalidate()
        }
    }
}

private struct PasteboardSnapshot {
    let types: Set<NSPasteboard.PasteboardType>
    let detectedContentType: UTType?

    private static let transientTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]

    var shouldSkipHistory: Bool {
        !types.isDisjoint(with: Self.transientTypes)
    }

    var canContainFileURL: Bool {
        types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    var canContainImage: Bool {
        types.contains(.png)
            || types.contains(.tiff)
            || detectedContentType?.conforms(to: .image) == true
    }

    var canContainRichText: Bool {
        types.contains(.rtf) && types.contains(.string)
    }

    var canContainPlainText: Bool {
        types.contains(.string)
    }
}
