import AppKit
import SwiftUI

struct QuickPanelStatusMessage: Equatable {
    let id = UUID()
    let message: String
    let kind: QuickPanelStatusKind
}

struct QuickPanelStatusBannerView: View {
    let banner: QuickPanelStatusMessage

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(banner.kind.tint.opacity(0.14))
                    .frame(width: 24, height: 24)

                HugeIconView(name: banner.kind.hugeIconName, fallbackSystemName: banner.kind.symbolName)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(banner.kind.tint)
            }

            Text(banner.message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .frame(minHeight: 42)
        .frame(maxWidth: 420)
        .background {
            if reduceTransparency {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.16))
                    .glassEffect(.regular, in: shape)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(banner.message)
    }
}

struct QuickPanelOnboardingView: View {
    let hotKeyPreset: HotKeyPreset
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
                HugeIconView(name: "ai-content-generator-01", fallbackSystemName: "doc.on.clipboard.fill")
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.tint)

                Text("欢迎使用 PastePop")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    onboardingLine(hotKeyPreset.symbols, "在任意 App 呼出 / 隐藏这个面板")
                    onboardingLine("← →", "左右浏览 · 按空格放大预览")
                    onboardingLine("回车", "把选中内容复制到剪贴板")
                    onboardingLine("⌘P / ⌘⌫", "固定常用内容 / 删除选中")
                }
                .font(.callout)

                Text("呼出快捷键是 \(hotKeyPreset.displayName)。想按回车后自动粘贴回刚才的 App，可以在设置里开启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("开始使用", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
        }
    }

    private func onboardingLine(_ key: String, _ description: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.callout.monospaced())
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct QuickPanelPreviewView: View {
    let clip: ClipItem
    let returnActionTitle: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.24))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            previewPanel
                .padding(20)
        }
    }

    private var previewPanel: some View {
        let shellShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(alignment: .leading, spacing: 12) {
            previewHeader
            previewContentSurface
        }
        .padding(14)
        .frame(maxWidth: 560, maxHeight: 306)
        .background {
            if reduceTransparency {
                shellShape
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shellShape
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.14))
                    .glassEffect(.regular, in: shellShape)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 6)
    }

    private var previewHeader: some View {
        HStack(spacing: 8) {
            HugeIconView(name: clip.kind.hugeIconName, fallbackSystemName: clip.kind.symbolName)
                .foregroundStyle(clip.kind.accent)
                .frame(width: 15, height: 15)

            Text(clip.kind.displayName)
                .fontWeight(.semibold)

            if let customName = clip.customName {
                Text(customName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Text(clip.source)
                .foregroundStyle(.secondary)

            Spacer()

            Text("空格 / Esc 关闭 · Return \(returnActionTitle)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 4)
    }

    private var previewContentSurface: some View {
        let contentShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return previewBody
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                contentShape
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.94))
            }
    }

    @ViewBuilder
    private var previewBody: some View {
        let mono = clip.kind == .code || clip.kind == .json || clip.kind == .command

        if clip.isSensitive {
            VStack(spacing: 6) {
                Text("敏感内容已隐藏")
                    .foregroundStyle(.secondary)

                Text("为保护隐私没有保存原文，需要时请回到原来的 App 重新复制。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if
            clip.kind == .image,
            let filename = clip.attachmentFilename,
            let data = ClipBlobStore.read(filename: filename),
            let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(clip.content)
                    .font(mono ? .system(.callout, design: .monospaced) : .callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

extension QuickPanelStatusKind {
    var hugeIconName: String {
        switch self {
        case .success:
            "checkmark-circle-02"
        case .warning:
            "alert-02"
        case .info:
            "information-circle"
        }
    }

    var symbolName: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .info:
            "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            .green
        case .warning:
            .orange
        case .info:
            .blue
        }
    }
}
