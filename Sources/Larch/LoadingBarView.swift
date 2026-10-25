import AppKit

/// 網頁卡片頂端的載入進度條：真實進度（estimatedProgress），開始淡入、完成衝到 100% 後淡出。
/// 不接收滑鼠事件，不影響網頁點擊與捲動。
@MainActor
final class LoadingBarView: NSView {
    static let height: CGFloat = 3
    private let fill = CALayer()
    private var token = 0
    /// 目前是否處於「載入中」。
    private(set) var isActive = false
    /// 目前顯示的進度（0...1）。
    private(set) var fraction: Double = 0
    var layerAlpha: Float { layer?.opacity ?? 0 }
    var isVisible: Bool { layerAlpha > 0.01 }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.opacity = 0
        fill.backgroundColor = Theme.progress.cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        applyFraction(animated: false)
    }

    private func applyFraction(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.2) }
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }

    private func setOpacity(_ v: Float, animated: Bool, duration: CFTimeInterval = 0.25) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(duration) }
        layer?.opacity = v
        CATransaction.commit()
    }

    /// 同步狀態。animated: false 用於切換 Tab（立即反映該 Tab 自己的狀態）。
    func update(loading: Bool, progress: Double, animated: Bool = true) {
        token += 1
        let mine = token
        if loading {
            if !isActive || !animated {
                fraction = 0
                applyFraction(animated: false)
            }
            isActive = true
            fraction = max(fraction, min(max(progress, 0.08), 0.95))
            setOpacity(1, animated: animated && !isVisible, duration: 0.1)
            applyFraction(animated: animated)
        } else {
            let wasActive = isActive
            isActive = false
            guard wasActive, animated else {
                fraction = 0
                applyFraction(animated: false)
                setOpacity(0, animated: false)
                return
            }
            fraction = 1
            applyFraction(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.token == mine, !self.isActive else { return }
                self.setOpacity(0, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.token == mine else { return }
                    self.fraction = 0
                    self.applyFraction(animated: false)
                }
            }
        }
    }
}
