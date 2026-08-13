import AppKit
import SwiftUI

/// Paste 式剪贴板卡片：彩色头部（类型 + 时间 + 类型图标）+ 正文预览 + 来源 + pin。
/// 卡片不绘制选中态；最新信息由卡片顺序表达。
struct ClipCardView: View {
    let clip: ClipItem
    let searchQuery: String
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onTogglePin: () -> Void

    /// 上次点击时间，用于自己判断双击，避免 SwiftUI 单/双击消歧带来的选中延迟。
    @State private var lastTapTime = Date.distantPast
    @State private var isHovering = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 附件型懒加载：图片缩略图 / 富文本富排版，从 blob 读出后缓存。
    @State private var loadedImage: NSImage?
    @State private var loadedRichText: AttributedString?
    /// 来源 App 图标，从 bundle id 解析后缓存。
    @State private var sourceIcon: NSImage?
    /// 链接预览（仅 URL 且用户开启时联网抓取）。
    @State private var linkTitle: String?
    @State private var linkIcon: NSImage?

    static let width: CGFloat = 208
    static let height: CGFloat = 272
    private static let cornerRadius: CGFloat = 14

    init(
        clip: ClipItem,
        searchQuery: String = "",
        onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onTogglePin: @escaping () -> Void
    ) {
        self.clip = clip
        self.searchQuery = searchQuery
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onTogglePin = onTogglePin
    }

    private var isMonospaced: Bool {
        clip.kind == .code || clip.kind == .json || clip.kind == .command
    }

    private var timeText: String {
        let relative = clip.relativeTime
        // 「刚刚」「昨天」本身就是完整表达，加「前」会变成「昨天前」。
        if relative == "刚刚" || relative == "昨天" {
            return relative
        }
        return relative + "前"
    }

    private var searchMatchLabel: String? {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        if containsQuery(clip.displayTitle, query: trimmedQuery) {
            return "标题"
        }
        if containsQuery(clip.kind.displayName, query: trimmedQuery) {
            return "类型"
        }
        if containsQuery(clip.source, query: trimmedQuery) {
            return "来源"
        }
        if containsQuery(clip.preview, query: trimmedQuery) || containsQuery(clip.content, query: trimmedQuery) {
            return "正文"
        }

        // 只有模糊打分命中、子串不命中时走到这里；「相关」对普通用户没有信息量，不显示。
        return nil
    }

    /// 只在按下瞬间缩小作反馈；hover / selected 不再整体放大。
    /// 这张卡用了 compositingGroup 处理圆角抗锯齿，整体放大会把文字当纹理采样，导致发糊。
    private var pressScale: CGFloat {
        if reduceMotion { return 1 }
        return isPressed ? 0.98 : 1
    }

    private var liftOffset: CGFloat {
        if reduceMotion { return 0 }
        return isHovering ? -2 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .textBackgroundColor))
        // 先把彩色头部 + 正文 + 白底压成一层再裁切，避免圆角处层间抗锯齿缝隙漏出白边。
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .scaleEffect(pressScale)
        .offset(y: liftOffset)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            guard !reduceMotion else {
                isHovering = hovering
                return
            }
            withAnimation(hovering ? Motion.hoverIn : Motion.hoverOut) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) < 0.3 {
                onActivate()
            } else {
                onSelect()
            }
            lastTapTime = now
        }
        // 真实按下反馈：mouse-down 即 0.98，松手回弹（长按本身不触发动作）。
        // macOS 上卡片墙滚动走 scrollWheel 事件而非拖拽手势，与此手势不冲突。
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 4, perform: {}, onPressingChanged: { pressing in
            guard !reduceMotion else {
                isPressed = false
                return
            }
            withAnimation(pressing ? Motion.pressDown : Motion.pressUp) {
                isPressed = pressing
            }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.kind.displayName)，\(clip.displayTitle)，\(timeText)复制自 \(clip.source)")
        // 卡片合并为单一无障碍元素后，行内 pin 按钮不再单独可达；用自定义动作补上。
        .accessibilityAction(named: Text(clip.isPinned ? "取消固定" : "固定")) {
            onTogglePin()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.kind.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            HugeIconView(name: clip.kind.hugeIconName, fallbackSystemName: clip.kind.symbolName)
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.16), in: Circle())
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(clip.kind.accent)
    }

    private var content: some View {
        Group {
            if clip.kind == .image, !clip.isSensitive {
                imageContent
            } else {
                standardContent
            }
        }
        .onAppear {
            loadSourceIcon()
        }
        .task(id: clip.attachmentFilename) {
            await loadAttachmentIfNeeded()
        }
        .task(id: linkPreviewTaskID) {
            await loadLinkPreviewIfNeeded()
        }
    }

    private var linkPreviewTaskID: String? {
        guard clip.kind == .url, AppSettings.shared.linkPreviewsEnabled else {
            return nil
        }
        return clip.content
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let customName = clip.customName {
                Text(customName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.bottom, 8)
            }

            bodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var imageContent: some View {
        ZStack(alignment: .bottom) {
            imageCanvas

            imageOverlay
        }
        .frame(width: Self.width, height: Self.height - 52)
        .clipped()
    }

    /// 抓取链接预览：仅当是 URL、用户开启了链接预览、且尚未加载时。命中缓存直接用，否则联网。
    private func loadLinkPreviewIfNeeded() async {
        guard
            clip.kind == .url,
            AppSettings.shared.linkPreviewsEnabled,
            linkTitle == nil, linkIcon == nil,
            let url = URL(string: clip.content)
        else {
            return
        }

        if let cached = LinkPreview.cached(for: clip.content) {
            applyLinkResult(cached)
            return
        }

        guard let result = await LinkPreview.fetch(url), !Task.isCancelled else { return }
        LinkPreview.store(result, for: clip.content)
        applyLinkResult(result)
    }

    private func applyLinkResult(_ result: LinkPreview.Result) {
        if let title = result.title, !title.isEmpty {
            linkTitle = title
        }
        if let data = result.iconPNG {
            linkIcon = NSImage(data: data)
        }
    }

    /// 从 bundle id 解析来源 App 图标。
    private func loadSourceIcon() {
        guard
            sourceIcon == nil,
            let bundleID = clip.sourceBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return
        }
        sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if clip.isSensitive {
            sensitiveBody
        } else if clip.kind == .image {
            imageCanvas
        } else if clip.kind == .file {
            fileBody
        } else if clip.kind == .url, linkTitle != nil || linkIcon != nil {
            // 仅当链接预览开启且抓到标题 / 图标时才用富预览；默认与纯文本预览一致。
            urlBody
        } else if clip.kind == .richText, let loadedRichText {
            richTextPreviewBody(loadedRichText)
        } else {
            textBody
        }
    }

    private var textBody: some View {
        textPreviewBody(
            Text(textPreviewText),
            font: isMonospaced ? .system(.body, design: .monospaced) : .body
        )
    }

    private func richTextPreviewBody(_ text: AttributedString) -> some View {
        textPreviewBody(Text(text), font: .body)
    }

    private func textPreviewBody(_ text: Text, font: Font) -> some View {
        fadingText(text, font: font)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fadingText(_ text: Text, font: Font) -> some View {
        ZStack(alignment: .bottom) {
            text
                .font(font)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(7)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            cardBottomFade(height: 16, color: Color(nsColor: .textBackgroundColor))
        }
    }

    private var textPreviewText: String {
        if clip.kind == .json {
            return jsonPreviewText
        }

        if clip.kind == .command {
            return commandPreviewText
        }

        return clip.content
    }

    private var codeBody: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(clip.kind.accent.opacity(0.28))
                .frame(width: 3)

            Text(linePreview(from: clip.content, limit: 8))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commandBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green.opacity(0.75))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(.yellow.opacity(0.75))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(.red.opacity(0.75))
                    .frame(width: 6, height: 6)

                Spacer(minLength: 0)
            }

            Text(commandPreviewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var jsonBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(jsonMetaText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(clip.kind.accent)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HugeIconView(name: "third-bracket", fallbackSystemName: "curlybraces")
                    .frame(width: 11, height: 11)
                    .foregroundStyle(clip.kind.accent.opacity(0.75))
            }

            Text(linePreview(from: jsonPreviewText, limit: 8))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(clip.kind.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(clip.kind.accent.opacity(0.14), lineWidth: 1)
        }
    }

    private var emailBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                HugeIconView(name: "mail-01", fallbackSystemName: "envelope")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(clip.kind.accent)

                Text(clip.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Text(clip.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .lineLimit(5)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var imageCanvas: some View {
        if let loadedImage {
            Image(nsImage: loadedImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.width, height: Self.height - 52)
                .clipped()
        } else {
            HugeIconView(name: "image-02", fallbackSystemName: "photo")
                .frame(width: 30, height: 30)
                .foregroundStyle(.tertiary)
                .frame(width: Self.width, height: Self.height - 52)
                .background(Color.primary.opacity(0.04))
        }
    }

    private var imageOverlay: some View {
        ZStack(alignment: .bottom) {
            cardBottomFade(height: clip.customName == nil ? 42 : 58, color: .black.opacity(0.5))

            imageFooter
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private var imageFooter: some View {
        HStack(spacing: 5) {
            if let sourceIcon {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 1) {
                if let customName = clip.customName {
                    Text(customName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(clip.source)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            PinButton(
                isPinned: clip.isPinned,
                idleTint: .white.opacity(0.78),
                reduceMotion: reduceMotion,
                action: onTogglePin
            )
            .opacity(clip.isPinned || isHovering ? 1 : 0)
            .accessibilityLabel(clip.isPinned ? "取消固定" : "固定")
        }
    }

    private func cardBottomFade(height: CGFloat, color: Color) -> some View {
        LinearGradient(
            colors: [
                color.opacity(0),
                color
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }

    private var fileBody: some View {
        let firstPath = clip.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: firstPath))
                .resizable()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(firstPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var richTextBody: some View {
        if let loadedRichText {
            Text(loadedRichText)
                .lineSpacing(3)
                .lineLimit(9)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            textBody
        }
    }

    /// URL：抓到链接预览（开启时）就显示 favicon + 标题 + 链接，否则退回纯文本。
    @ViewBuilder
    private var urlBody: some View {
        if linkTitle != nil || linkIcon != nil {
            urlPreviewBody(title: linkTitle ?? urlHostText, icon: linkIcon)
        } else {
            urlPreviewBody(title: urlHostText, icon: nil)
        }
    }

    private func urlPreviewBody(title: String, icon: NSImage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            urlPreviewSurface(icon: icon)

            HStack(alignment: .top, spacing: 7) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 17, height: 17)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    HugeIconView(name: "link-01", fallbackSystemName: "link")
                        .frame(width: 16, height: 16)
                        .foregroundStyle(clip.kind.accent)
                }

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Text(urlPathText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(clip.content)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func urlPreviewSurface(icon: NSImage?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    HugeIconView(name: "link-01", fallbackSystemName: "link")
                        .frame(width: 12, height: 12)
                        .foregroundStyle(clip.kind.accent)
                }
            }
            .frame(width: 28, height: 28)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: Circle())

            Text(urlHostText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(clip.kind.accent.opacity(0.12))

                Circle()
                    .fill(clip.kind.accent.opacity(0.1))
                    .frame(width: 72, height: 72)
                    .offset(x: 24, y: -18)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(clip.kind.accent.opacity(0.16), lineWidth: 1)
        }
    }

    private var urlHostText: String {
        guard let host = urlDisplayComponents?.host else {
            return clip.title
        }

        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var urlPathText: String {
        guard let components = urlDisplayComponents else {
            return clip.content
        }

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let fragment = components.percentEncodedFragment.map { "#\($0)" } ?? ""
        let display = path + query + fragment

        return display == "/" ? "/" : display
    }

    private var urlDisplayComponents: URLComponents? {
        if let components = URLComponents(string: clip.content), components.host != nil {
            return components
        }

        return URLComponents(string: "https://\(clip.content)")
    }

    private var commandPreviewText: String {
        linePreview(from: clip.content, limit: 6, trimsWhitespace: true)
            .components(separatedBy: .newlines)
            .map { "$ \($0)" }
            .joined(separator: "\n")
    }

    private var jsonMetaText: String {
        guard let jsonObject else {
            return "JSON"
        }

        if let dictionary = jsonObject as? [String: Any] {
            return "\(dictionary.count) 项"
        }

        if let array = jsonObject as? [Any] {
            return "\(array.count) 项"
        }

        return "数据"
    }

    private var jsonPreviewText: String {
        guard let jsonObject else {
            return clip.content
        }

        if
            JSONSerialization.isValidJSONObject(jsonObject),
            let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        {
            return text
        }

        return String(describing: jsonObject)
    }

    private var jsonObject: Any? {
        guard let data = clip.content.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func linePreview(from text: String, limit: Int, trimsWhitespace: Bool = false) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { trimsWhitespace ? $0.trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if lines.isEmpty {
            return text
        }

        return lines.prefix(limit).joined(separator: "\n")
    }

    /// 从 blob 懒加载图片缩略图 / 富文本富排版；磁盘读取与解码不阻塞主线程。
    private func loadAttachmentIfNeeded() async {
        guard let filename = clip.attachmentFilename else {
            return
        }

        switch clip.kind {
        case .image where loadedImage == nil:
            guard
                let data = await ImageThumbnailCache.shared.data(for: filename),
                !Task.isCancelled
            else {
                return
            }
            loadedImage = NSImage(data: data)
        case .richText where loadedRichText == nil:
            let attributed = await Task.detached(priority: .utility) { () -> AttributedString? in
                guard
                    let data = ClipBlobStore.read(filename: filename),
                    let ns = try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                else {
                    return nil
                }
                return AttributedString(ns)
            }.value
            guard !Task.isCancelled else { return }
            loadedRichText = attributed
        default:
            break
        }
    }

    private var sensitiveBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HugeIconView(name: "square-lock-01", fallbackSystemName: "lock")
                .frame(width: 20, height: 20)
                .foregroundStyle(clip.kind.tint)

            Text("敏感内容已隐藏")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("像是密码或验证码，为保护隐私没有保存原文。需要时请回到原来的 App 重新复制。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let sourceIcon {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }

            Text(clip.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let searchMatchLabel {
                Text(searchMatchLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(clip.kind.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(clip.kind.accent.opacity(0.1), in: Capsule())
                    .accessibilityLabel("搜索命中\(searchMatchLabel)")
            }

            PinButton(
                isPinned: clip.isPinned,
                idleTint: .secondary,
                reduceMotion: reduceMotion,
                action: onTogglePin
            )
            .opacity(clip.isPinned || isHovering ? 1 : 0)
            .accessibilityLabel(clip.isPinned ? "取消固定" : "固定")
        }
    }

    private func containsQuery(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

#Preview {
    HStack(spacing: 14) {
            ClipCardView(clip: MockClips.all[0], onSelect: {}, onActivate: {}, onTogglePin: {})
            ClipCardView(clip: MockClips.all[3], onSelect: {}, onActivate: {}, onTogglePin: {})
            ClipCardView(clip: MockClips.all[6], onSelect: {}, onActivate: {}, onTogglePin: {})
    }
    .padding(40)
    .background(.regularMaterial)
}

/// pin 按钮：Hugeicons 图标 + 固定状态切换时一次轻微放大脉冲（等价原 SF Symbol bounce）。
private struct PinButton: View {
    let isPinned: Bool
    let idleTint: Color
    let reduceMotion: Bool
    let action: () -> Void

    @State private var bouncing = false
    @State private var bounceTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            HugeIconView(name: isPinned ? "pin-solid" : "pin", fallbackSystemName: isPinned ? "pin.fill" : "pin")
                .frame(width: 13, height: 13)
                .foregroundStyle(isPinned ? Color.accentColor : idleTint)
                .scaleEffect(bouncing ? 1.10 : 1)
        }
        .buttonStyle(.plain)
        .onChange(of: isPinned) {
            guard !reduceMotion else { return }
            bounceTask?.cancel()
            withAnimation(Motion.pinConfirmation) { bouncing = true }
            bounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.pinConfirmation) { bouncing = false }
            }
        }
        .onDisappear {
            bounceTask?.cancel()
            bounceTask = nil
        }
    }
}
