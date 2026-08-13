import SwiftUI

/// 面板背景使用轻量模糊和半透明底色；内容卡片仍保持实底，保证剪贴板内容可读。
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    ZStack {
                        shape
                            .fill(.ultraThinMaterial)
                        shape
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.38))
                    }
                }
            }
            .clipShape(shape)
    }
}

extension View {
    func panelBackground(cornerRadius: CGFloat) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}
