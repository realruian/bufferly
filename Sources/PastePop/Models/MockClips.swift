import Foundation

enum MockClips {
    static let all: [ClipItem] = [
        ClipItem(
            kind: .json,
            title: "API response",
            preview: #"{"status":"ok","items":[{"id":"clip_01","type":"command"}]}"#,
            source: "Safari",
            content: #"{"status":"ok","items":[{"id":"clip_01","type":"command"}]}"#,
            isPinned: true
        ),
        ClipItem(
            kind: .command,
            title: "Build command",
            preview: "swift build && swift test",
            source: "Terminal",
            content: "swift build && swift test",
            isPinned: true
        ),
        ClipItem(
            kind: .text,
            title: "Rewrite prompt",
            preview: "Rewrite this with a concise, native macOS product tone.",
            source: "ChatGPT",
            content: "Rewrite this with a concise, native macOS product tone.",
            isPinned: true
        ),
        ClipItem(
            kind: .url,
            title: "Apple Human Interface Guidelines",
            preview: "developer.apple.com/design/human-interface-guidelines",
            source: "Safari",
            content: "developer.apple.com/design/human-interface-guidelines"
        ),
        ClipItem(
            kind: .code,
            title: "SwiftUI row state",
            preview: "struct ClipRowView: View { let clip: ClipItem; let isSelected: Bool }",
            source: "Xcode",
            content: "struct ClipRowView: View { let clip: ClipItem; let isSelected: Bool }"
        ),
        ClipItem(
            kind: .email,
            title: "Contact",
            preview: "hello@pastepop.local",
            source: "Mail",
            content: "hello@pastepop.local"
        ),
        ClipItem(
            kind: .secret,
            title: "Sensitive content hidden",
            preview: "This clip matched the sensitive content filter.",
            source: "Terminal",
            content: "This clip matched the sensitive content filter.",
            isSensitive: true
        )
    ]
}
