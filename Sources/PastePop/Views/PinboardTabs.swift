import AppKit
import SwiftUI

/// 「剪贴板 / 已固定」分段切换：外层用官方 Liquid Glass，选中 pill 用实底保证可读。
///
/// 参考 Transitions.dev「Tabs sliding」：药丸用 matchedGeometryEffect 在选中 tab 后面
/// 滑动（位置 + 宽度一起补间），缓动 = cubic-bezier(0.22, 1, 0.36, 1) / 200ms，
/// 文字仅做颜色过渡（muted ↔ active，不变字重，避免宽度跳动）。尊重 Reduce Motion。
struct PinboardTabs: View {
    @Binding var selection: QuickPanelViewModel.Board

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(QuickPanelViewModel.Board.allCases) { board in
                    tab(board)
                }
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 0.96 : 0.18))
        }
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Capsule(style: .continuous))
    }

    /// 真正的 Button（而非 Text + 手势）：Full Keyboard Access / VoiceOver 可以到达。
    private func tab(_ board: QuickPanelViewModel.Board) -> some View {
        let isSelected = selection == board

        return Button {
            guard selection != board else { return }
            if reduceMotion {
                selection = board
            } else {
                withAnimation(Motion.tabSlide) {
                    selection = board
                }
            }
        } label: {
            Text(board.rawValue)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.82))
                .animation(reduceMotion ? Motion.reducedFade : Motion.tabSlide, value: isSelected)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                            .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
                            .matchedGeometryEffect(id: "pinboardPill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
