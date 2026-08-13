import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class QuickPanelWindowController: NSWindowController, NSWindowDelegate {
    var onVisibilityChange: ((Bool) -> Void)?
    var onDidHide: (() -> Void)?

    private var visibilityAnimationID = UUID()
    private var visibilityTask: Task<Void, Never>?
    private var isHiding = false
    private let animationView: NSView

    private struct LayerState {
        let transform: CATransform3D
        let opacity: Float
    }

    private enum VisibilityAnimation {
        static let showOffsetY: CGFloat = 18
        static let hideOffsetY: CGFloat = 12
        static let showInitialAlpha: Float = 0.45
        static let showDuration: TimeInterval = 0.24
        static let hideDuration: TimeInterval = 0.20
        static let reducedMotionDuration: TimeInterval = 0.12
    }

    private enum PanelShadow {
        static let radius: CGFloat = 24
        static let offsetY: CGFloat = 8
        static let opacity = 0.16
        // 高斯模糊的可见尾部会超过 radius；预留 radius * 2 + offset，避免窗口边界裁切。
        static let padding: CGFloat = radius * 2 + offsetY
    }

    var isPanelVisible: Bool {
        window?.isVisible == true && !isHiding
    }

    init(viewModel: QuickPanelViewModel = QuickPanelViewModel()) {
        let contentView = QuickPanelView(viewModel: viewModel)
            .shadow(
                color: .black.opacity(PanelShadow.opacity),
                radius: PanelShadow.radius,
                x: 0,
                y: PanelShadow.offsetY
            )
            .padding(PanelShadow.padding)
        let hostingView = NSHostingView(rootView: contentView)
        // 用可成为 key 的子类：无边框窗口默认 canBecomeKey=false，
        // 否则窗口收不到键盘、也永远不会触发 resignKey（失焦自动隐藏因此失效）。
        let window = KeyablePanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 980 + PanelShadow.padding * 2,
                height: QuickPanelView.panelHeight + PanelShadow.padding * 2
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let animationView = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        animationView.wantsLayer = true
        animationView.layer?.allowsGroupOpacity = true
        hostingView.frame = animationView.bounds
        hostingView.autoresizingMask = [.width, .height]
        animationView.addSubview(hostingView)

        window.contentView = animationView
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        // 原生窗口投影自带贴边深色 contact shadow，无法单独调整。
        // 关闭它，改用上方预留透明空间的柔和投影，避免出现外圈硬描边。
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .transient]
        window.isReleasedWhenClosed = false

        self.animationView = animationView
        super.init(window: window)

        window.delegate = self
    }

    /// 把面板贴到当前屏幕底部居中，按屏幕宽度铺开（留边），类似 Paste 的底部卡片条。
    private func positionAtBottom() {
        guard let window else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let horizontalMargin: CGFloat = 24
        let bottomGap: CGFloat = 24
        let panelWidth = min(visibleFrame.width - horizontalMargin * 2, 1_280)
        let width = panelWidth + PanelShadow.padding * 2
        let height = QuickPanelView.panelHeight + PanelShadow.padding * 2
        let originX = visibleFrame.midX - width / 2
        let originY = visibleFrame.minY + bottomGap - PanelShadow.padding

        window.setFrame(
            NSRect(x: originX, y: originY, width: width, height: height),
            display: true
        )
    }

    func showPanel(animated: Bool = true) {
        guard let window else {
            return
        }

        if window.isVisible && !isHiding {
            positionAtBottom()
            resetAnimationLayer()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            onVisibilityChange?(true)
            NotificationCenter.default.post(name: .quickPanelDidShow, object: nil)
            NotificationCenter.default.post(name: .quickPanelDidFinishShowing, object: nil)
            return
        }

        let animationID = UUID()
        visibilityAnimationID = animationID
        let wasVisible = window.isVisible
        let currentState = currentLayerState()
        cancelVisibilityAnimation()
        isHiding = false

        positionAtBottom()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let startState: LayerState

        if animated, wasVisible {
            // 快速反向操作从当前视觉位置接续，不重新跳回动画起点。
            startState = currentState
        } else if animated {
            startState = LayerState(
                transform: reduceMotion
                    ? CATransform3DIdentity
                    : CATransform3DMakeTranslation(0, -VisibilityAnimation.showOffsetY, 0),
                opacity: VisibilityAnimation.showInitialAlpha
            )
        } else {
            startState = LayerState(transform: CATransform3DIdentity, opacity: 1)
        }

        setAnimationLayer(to: startState)
        // 首次创建时强制完成 SwiftUI 布局和初始绘制，避免这些工作挤进动画的前几帧。
        animationView.layoutSubtreeIfNeeded()
        animationView.displayIfNeeded()

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if animated {
            animateLayer(
                from: startState,
                to: LayerState(transform: CATransform3DIdentity, opacity: 1),
                duration: reduceMotion
                    ? VisibilityAnimation.reducedMotionDuration
                    : VisibilityAnimation.showDuration,
                timingFunction: reduceMotion
                    ? CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                    : CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1),
                animationID: animationID
            ) {
                NotificationCenter.default.post(name: .quickPanelDidFinishShowing, object: nil)
            }
        } else {
            resetAnimationLayer()
        }

        onVisibilityChange?(true)
        NotificationCenter.default.post(name: .quickPanelDidShow, object: nil)
        if !animated {
            NotificationCenter.default.post(name: .quickPanelDidFinishShowing, object: nil)
        }
    }

    func hidePanel(animated: Bool = true) {
        guard let window, window.isVisible else {
            isHiding = false
            onVisibilityChange?(false)
            onDidHide?()
            return
        }
        guard !isHiding else {
            return
        }

        let animationID = UUID()
        visibilityAnimationID = animationID
        let startState = currentLayerState()
        cancelVisibilityAnimation()
        isHiding = true
        onVisibilityChange?(false)

        guard animated else {
            window.orderOut(nil)
            resetAnimationLayer()
            isHiding = false
            onDidHide?()
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let endState = LayerState(
            transform: reduceMotion
                ? CATransform3DIdentity
                : CATransform3DMakeTranslation(0, -VisibilityAnimation.hideOffsetY, 0),
            opacity: 0
        )

        animateLayer(
            from: startState,
            to: endState,
            duration: reduceMotion
                ? VisibilityAnimation.reducedMotionDuration
                : VisibilityAnimation.hideDuration,
            timingFunction: CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1),
            animationID: animationID
        ) { [weak self, weak window] in
            guard let self else { return }
            window?.orderOut(nil)
            self.resetAnimationLayer()
            self.isHiding = false
            self.onDidHide?()
        }
    }

    private func animateLayer(
        from startState: LayerState,
        to endState: LayerState,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        animationID: UUID,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let layer = animationView.layer else {
            completion()
            return
        }

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: startState.transform)
        transform.toValue = NSValue(caTransform3D: endState.transform)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = startState.opacity
        opacity.toValue = endState.opacity

        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = duration
        group.timingFunction = timingFunction

        setAnimationLayer(to: endState)
        layer.add(group, forKey: "visibility")

        visibilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard
                !Task.isCancelled,
                let self,
                self.visibilityAnimationID == animationID
            else {
                return
            }
            self.visibilityTask = nil
            completion()
        }
    }

    private func currentLayerState() -> LayerState {
        guard let layer = animationView.layer else {
            return LayerState(transform: CATransform3DIdentity, opacity: 1)
        }
        let visibleLayer = layer.presentation() ?? layer
        return LayerState(transform: visibleLayer.transform, opacity: visibleLayer.opacity)
    }

    private func setAnimationLayer(to state: LayerState) {
        guard let layer = animationView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = state.transform
        layer.opacity = state.opacity
        CATransaction.commit()
    }

    private func resetAnimationLayer() {
        cancelVisibilityAnimation()
        setAnimationLayer(to: LayerState(transform: CATransform3DIdentity, opacity: 1))
    }

    private func cancelVisibilityAnimation() {
        visibilityTask?.cancel()
        visibilityTask = nil
        animationView.layer?.removeAnimation(forKey: "visibility")
    }

    func windowDidResignKey(_ notification: Notification) {
        hidePanel(animated: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

/// 无边框面板窗口。覆写 canBecomeKey/Main，使其能接收键盘输入，
/// 并在点击其它界面失焦时正常触发 windowDidResignKey 以自动隐藏。
private final class KeyablePanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
