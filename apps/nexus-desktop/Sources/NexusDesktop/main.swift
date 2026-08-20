import AppKit
import Foundation
import LocalAuthentication
import Security

// MARK: - 颜色与小组件

enum Palette {
    // AI Dev One 的深森林玻璃色板：克制、低饱和，并始终保持深色模式。
    static let sidebar = NSColor(calibratedRed: 0.018, green: 0.085, blue: 0.105, alpha: 0.72)
    static let canvas = NSColor(calibratedRed: 0.012, green: 0.055, blue: 0.075, alpha: 0.58)
    static let elevated = NSColor(calibratedRed: 0.028, green: 0.105, blue: 0.13, alpha: 0.62)
    static let subtle = NSColor(calibratedRed: 0.035, green: 0.17, blue: 0.19, alpha: 0.70)
    static let selected = NSColor(calibratedRed: 0.03, green: 0.24, blue: 0.26, alpha: 0.78)
    static let border = NSColor(calibratedRed: 0.47, green: 1.0, blue: 0.94, alpha: 0.16)
    static let secondaryText = NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.66, alpha: 0.9)
    static let accent = NSColor(calibratedRed: 0.176, green: 0.886, blue: 0.902, alpha: 1)
    static let violet = NSColor(calibratedRed: 0.608, green: 0.486, blue: 1.0, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.243, green: 0.549, blue: 1.0, alpha: 1)
    static let success = NSColor(calibratedRed: 0.224, green: 0.902, blue: 0.647, alpha: 1)
    static let warning = NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.34, alpha: 1)
    static let error = NSColor(calibratedRed: 0.98, green: 0.32, blue: 0.42, alpha: 1)
    static let deepGreen = NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.28, alpha: 1)
    static let forestTop = NSColor(calibratedRed: 0.024, green: 0.118, blue: 0.11, alpha: 1)
    static let forestBottom = NSColor(calibratedRed: 0.008, green: 0.025, blue: 0.08, alpha: 1)
}

final class GlassEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class GlassHighlightView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor.white.withAlphaComponent(0.055).cgColor, NSColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        )
        guard let gradient else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: bounds.height),
            end: CGPoint(x: 0, y: bounds.height * 0.56),
            options: []
        )
    }
}

class LayerView: NSView {
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var strokeColor: NSColor? {
        didSet { needsDisplay = true }
    }
    private var glassEffect: GlassEffectView?
    private var highlightView: GlassHighlightView?

    init(fillColor: NSColor = .clear, cornerRadius: CGFloat = 0, strokeColor: NSColor? = nil) {
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.52).cgColor
        layer?.shadowOpacity = cornerRadius > 0 ? 0.42 : 0
        layer?.shadowRadius = cornerRadius > 0 ? 18 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -7)
        if cornerRadius >= 8 {
            let effect = GlassEffectView()
            effect.translatesAutoresizingMaskIntoConstraints = false
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.alphaValue = 0.54
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.masksToBounds = true
            addSubview(effect, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: trailingAnchor),
                effect.topAnchor.constraint(equalTo: topAnchor),
                effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            glassEffect = effect
            let highlight = GlassHighlightView()
            highlight.translatesAutoresizingMaskIntoConstraints = false
            highlight.wantsLayer = true
            highlight.layer?.cornerRadius = cornerRadius
            highlight.layer?.masksToBounds = true
            addSubview(highlight, positioned: .above, relativeTo: effect)
            NSLayoutConstraint.activate([
                highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
                highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
                highlight.topAnchor.constraint(equalTo: topAnchor),
                highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            highlightView = highlight
        }
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = strokeColor == nil ? 0 : 1
        layer?.borderColor = strokeColor?.cgColor
        layer?.shadowPath = cornerRadius > 0
            ? CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            : nil
    }

    override var wantsUpdateLayer: Bool { true }
}

/// 隔离 NSWindow 尺寸求解与 Renderer 内部 Auto Layout 的宿主。
///
/// hostedView 不通过约束连接到宿主，因此三栏内容的 fittingSize 不会反向
/// 改写窗口边界；宿主由系统 contentView 通过 frame/autoresize 管理。
final class WindowContentHostView: NSView {
    private let hostedView: NSView

    init(hostedView: NSView, frameSize: NSSize) {
        self.hostedView = hostedView
        super.init(frame: NSRect(origin: .zero, size: frameSize))
        autoresizesSubviews = false
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.frame = bounds
        hostedView.autoresizingMask = [.width, .height]
        addSubview(hostedView)
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func layout() {
        super.layout()
        hostedView.frame = bounds
        hostedView.needsLayout = true
        hostedView.layoutSubtreeIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostedView.frame = bounds
        hostedView.needsLayout = true
    }
}

/// 不依赖图片资源的荧光森林背景：用渐变、叶脉和微光粒子保持界面轻盈。
final class ForestBackdropView: NSView {
    private var phase: CGFloat = 0
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 6.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 保持原来的漂浮速度，只降低整层重绘频率，避免空闲窗口高 CPU。
            self.phase += 0.0021
            if self.phase > 1 { self.phase -= 1 }
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    deinit {
        animationTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        NSGradient(colors: [Palette.forestTop, Palette.canvas, Palette.forestBottom])?.draw(
            in: rect,
            angle: -18
        )

        context.saveGState()
        drawGlow(at: NSPoint(x: rect.width * 0.14, y: rect.height * 0.14), radius: 280, color: Palette.accent)
        drawGlow(at: NSPoint(x: rect.width * 0.87, y: rect.height * 0.82), radius: 250, color: Palette.violet)
        drawGlow(at: NSPoint(x: rect.width * 0.58, y: rect.height * 0.92), radius: 220, color: Palette.deepGreen)
        drawLeafVeins(in: rect)
        drawParticles(in: rect)
        drawGrain(in: rect, context: context)
        context.restoreGState()
    }

    private func drawGlow(at center: NSPoint, radius: CGFloat, color: NSColor) {
        for step in stride(from: 1.0, through: 0.12, by: -0.10) {
            let currentRadius = radius * step
            let alpha = CGFloat(0.008 + (1.0 - step) * 0.035)
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - currentRadius,
                    y: center.y - currentRadius,
                    width: currentRadius * 2,
                    height: currentRadius * 2
                )
            ).fill()
        }
    }

    private func drawLeafVeins(in rect: NSRect) {
        let paths: [(NSPoint, NSPoint, NSPoint, NSPoint, NSColor)] = [
            (
                NSPoint(x: -30, y: rect.height * 0.82),
                NSPoint(x: rect.width * 0.10, y: rect.height * 0.93),
                NSPoint(x: rect.width * 0.22, y: rect.height * 0.78),
                NSPoint(x: rect.width * 0.34, y: rect.height * 0.88),
                Palette.accent
            ),
            (
                NSPoint(x: rect.width * 0.54, y: rect.height * 0.16),
                NSPoint(x: rect.width * 0.66, y: rect.height * 0.32),
                NSPoint(x: rect.width * 0.84, y: rect.height * 0.40),
                NSPoint(x: rect.width + 30, y: rect.height * 0.63),
                Palette.violet
            ),
            (
                NSPoint(x: rect.width * 0.12, y: rect.height + 20),
                NSPoint(x: rect.width * 0.30, y: rect.height * 0.86),
                NSPoint(x: rect.width * 0.47, y: rect.height * 0.96),
                NSPoint(x: rect.width * 0.64, y: rect.height + 30),
                Palette.deepGreen
            ),
        ]
        for (start, c1, c2, end, color) in paths {
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
            path.lineWidth = 0.72
            color.withAlphaComponent(0.065).setStroke()
            path.stroke()

            for index in 1...4 {
                let ratio = CGFloat(index) / 5
                let point = NSPoint(
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio
                )
                let branch = NSBezierPath()
                branch.move(to: point)
                branch.line(to: NSPoint(x: point.x + 22, y: point.y + (index.isMultiple(of: 2) ? 16 : -16)))
                branch.lineWidth = 0.55
                color.withAlphaComponent(0.042).setStroke()
                branch.stroke()
            }
            for index in 1...5 {
                let ratio = CGFloat(index) / 6
                let node = NSPoint(
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio
                )
                let radius: CGFloat = index == 3 ? 2.0 : 1.0
                color.withAlphaComponent(index == 3 ? 0.24 : 0.09).setFill()
                NSBezierPath(ovalIn: NSRect(
                    x: node.x - radius,
                    y: node.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )).fill()
            }
        }
    }

    private func drawParticles(in rect: NSRect) {
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.18, 0.16, 1), (0.42, 0.79, 2), (0.56, 0.67, 1), (0.68, 0.84, 1),
            (0.88, 0.78, 2), (0.35, 0.30, 1), (0.79, 0.30, 1), (0.62, 0.56, 1),
        ]
        for (index, seed) in seeds.enumerated() {
            let (x, y, size) = seed
            let drift = sin(phase * .pi * 2 + CGFloat(index)) * 0.009
            let color = index.isMultiple(of: 3) ? Palette.violet : Palette.accent
            color.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.width * (x + drift),
                y: rect.height * (y + drift * 0.6),
                width: size,
                height: size
            )).fill()
        }
    }

    private func drawGrain(in rect: NSRect, context: CGContext) {
        // 极轻的颗粒，让大面积渐变不显得像一张平面色块。
        context.setFillColor(NSColor.white.withAlphaComponent(0.012).cgColor)
        var seed: UInt32 = 19
        for _ in 0..<150 {
            seed = 1664525 &* seed &+ 1013904223
            let x = CGFloat(seed % 1000) / 1000 * rect.width
            seed = 1664525 &* seed &+ 1013904223
            let y = CGFloat(seed % 1000) / 1000 * rect.height
            context.fill(CGRect(x: x, y: y, width: 0.55, height: 0.55))
        }
    }
}

// MARK: - AI Dev One 顶部与底部框架

final class TopBarView: LayerView {
    var onSettings: (() -> Void)?
    var onWorkMonitor: (() -> Void)?

    init() {
        super.init(fillColor: Palette.sidebar.withAlphaComponent(0.68), cornerRadius: 0, strokeColor: Palette.border)
        translatesAutoresizingMaskIntoConstraints = false

        let logo = LayerView(fillColor: Palette.accent.withAlphaComponent(0.13), cornerRadius: 17, strokeColor: Palette.accent.withAlphaComponent(0.45))
        logo.translatesAutoresizingMaskIntoConstraints = false
        let leaf = NSImageView()
        leaf.translatesAutoresizingMaskIntoConstraints = false
        leaf.image = symbol("leaf.fill", size: 18, weight: .medium)
        leaf.contentTintColor = Palette.accent
        logo.addSubview(leaf)
        leaf.pinEdges(to: logo, insets: NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7))

        let product = label("AI Dev One", size: 15, weight: .semibold, color: NSColor(calibratedWhite: 0.92, alpha: 1))
        product.translatesAutoresizingMaskIntoConstraints = false
        let route = label("Route 2", size: 12, color: Palette.secondaryText)
        route.translatesAutoresizingMaskIntoConstraints = false

        let core = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.72), cornerRadius: 18, strokeColor: Palette.border)
        core.translatesAutoresizingMaskIntoConstraints = false
        let coreLeaf = NSImageView()
        coreLeaf.translatesAutoresizingMaskIntoConstraints = false
        coreLeaf.image = symbol("leaf.fill", size: 12)
        coreLeaf.contentTintColor = Palette.accent
        let coreTitle = label("AI Dev One Core", size: 12.5, weight: .medium)
        coreTitle.translatesAutoresizingMaskIntoConstraints = false
        let coreVersion = label("v0.5.0-beta.1", size: 11, color: Palette.secondaryText)
        coreVersion.translatesAutoresizingMaskIntoConstraints = false
        let localDot = label("● Local Agent", size: 10.5, color: Palette.success)
        localDot.translatesAutoresizingMaskIntoConstraints = false
        let chevron = NSImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = symbol("chevron.down", size: 10, weight: .semibold)
        chevron.contentTintColor = Palette.secondaryText
        [coreLeaf, coreTitle, coreVersion, localDot, chevron].forEach(core.addSubview)
        NSLayoutConstraint.activate([
            coreLeaf.leadingAnchor.constraint(equalTo: core.leadingAnchor, constant: 14),
            coreLeaf.centerYAnchor.constraint(equalTo: core.centerYAnchor),
            coreLeaf.widthAnchor.constraint(equalToConstant: 16),
            coreLeaf.heightAnchor.constraint(equalToConstant: 16),
            coreTitle.leadingAnchor.constraint(equalTo: coreLeaf.trailingAnchor, constant: 7),
            coreTitle.centerYAnchor.constraint(equalTo: core.centerYAnchor),
            coreVersion.leadingAnchor.constraint(equalTo: coreTitle.trailingAnchor, constant: 6),
            coreVersion.centerYAnchor.constraint(equalTo: coreTitle.centerYAnchor),
            localDot.leadingAnchor.constraint(equalTo: coreVersion.trailingAnchor, constant: 16),
            localDot.centerYAnchor.constraint(equalTo: core.centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: localDot.trailingAnchor, constant: 14),
            chevron.trailingAnchor.constraint(equalTo: core.trailingAnchor, constant: -13),
            chevron.centerYAnchor.constraint(equalTo: core.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 13),
            chevron.heightAnchor.constraint(equalToConstant: 13),
        ])

        let search = HoverButton(frame: .zero)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.isBordered = false
        search.title = "  搜索 ⌘K"
        search.font = .systemFont(ofSize: 11.5)
        search.alignment = .left
        search.image = symbol("magnifyingglass", size: 12)
        search.imagePosition = .imageLeading
        search.contentTintColor = Palette.secondaryText
        search.wantsLayer = true
        search.layer?.cornerRadius = 16
        search.layer?.borderWidth = 1
        search.layer?.borderColor = Palette.border.cgColor
        search.normalColor = Palette.elevated.withAlphaComponent(0.4)
        search.hoverColor = Palette.subtle
        search.layer?.backgroundColor = search.normalColor.cgColor

        let bell = iconButton("bell", tooltip: "通知")
        let spark = iconButton("sparkles", tooltip: "工作监控")
        spark.contentTintColor = Palette.accent
        spark.target = self
        spark.action = #selector(workMonitorClicked)
        let settings = iconButton("gearshape", tooltip: "设置")
        settings.target = self
        settings.action = #selector(settingsClicked)

        [logo, product, route, core, search, spark, bell, settings].forEach(addSubview)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            logo.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 34),
            logo.heightAnchor.constraint(equalToConstant: 34),
            product.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 10),
            product.centerYAnchor.constraint(equalTo: centerYAnchor),
            route.leadingAnchor.constraint(equalTo: product.trailingAnchor, constant: 8),
            route.centerYAnchor.constraint(equalTo: centerYAnchor),
            core.centerXAnchor.constraint(equalTo: centerXAnchor),
            core.centerYAnchor.constraint(equalTo: centerYAnchor),
            core.widthAnchor.constraint(equalToConstant: 222),
            core.heightAnchor.constraint(equalToConstant: 36),
            settings.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            settings.centerYAnchor.constraint(equalTo: centerYAnchor),
            settings.widthAnchor.constraint(equalToConstant: 32),
            settings.heightAnchor.constraint(equalToConstant: 32),
            bell.trailingAnchor.constraint(equalTo: settings.leadingAnchor, constant: -7),
            bell.centerYAnchor.constraint(equalTo: centerYAnchor),
            bell.widthAnchor.constraint(equalToConstant: 32),
            bell.heightAnchor.constraint(equalToConstant: 32),
            spark.trailingAnchor.constraint(equalTo: bell.leadingAnchor, constant: -7),
            spark.centerYAnchor.constraint(equalTo: centerYAnchor),
            spark.widthAnchor.constraint(equalToConstant: 32),
            spark.heightAnchor.constraint(equalToConstant: 32),
            search.trailingAnchor.constraint(equalTo: spark.leadingAnchor, constant: -12),
            search.centerYAnchor.constraint(equalTo: centerYAnchor),
            search.widthAnchor.constraint(equalToConstant: 176),
            search.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    private func iconButton(_ imageName: String, tooltip: String) -> HoverButton {
        let button = HoverButton(frame: .zero)
        button.isBordered = false
        button.image = symbol(imageName, size: 14, weight: .medium)
        button.imagePosition = .imageOnly
        button.contentTintColor = Palette.secondaryText
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        button.layer?.borderWidth = 1
        button.layer?.borderColor = Palette.border.cgColor
        button.normalColor = Palette.elevated.withAlphaComponent(0.45)
        button.hoverColor = Palette.subtle
        button.layer?.backgroundColor = button.normalColor.cgColor
        button.toolTip = tooltip
        return button
    }

    @objc private func settingsClicked() { onSettings?() }
    @objc private func workMonitorClicked() { onWorkMonitor?() }
}

final class BottomStatusBarView: LayerView {
    private let coreStatus = label("●  Rust Core", size: 10.5, weight: .medium, color: Palette.success)
    private let modelStatus = label("●  模型就绪", size: 10.5, weight: .medium, color: Palette.success)
    private let agentStatus = label("○  Agent 空闲", size: 10.5, weight: .medium, color: Palette.secondaryText)
    private let restartCoreButton = NSButton(title: "重新启动 Core", target: nil, action: nil)
    private let viewCoreLogButton = NSButton(title: "查看日志", target: nil, action: nil)
    private let coreActions = NSStackView()

    var onRestartCore: (() -> Void)?
    var onViewCoreLog: (() -> Void)?

    init() {
        super.init(fillColor: Palette.sidebar.withAlphaComponent(0.7), cornerRadius: 0, strokeColor: Palette.border)
        translatesAutoresizingMaskIntoConstraints = false
        let version = label("◈  AI Dev One Core v0.5.0-beta.1", size: 11, color: Palette.secondaryText)
        let local = capsule("●  本地模式", color: Palette.success)
        let monitor = capsule("⌁  性能监控", color: Palette.accent)
        [restartCoreButton, viewCoreLogButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.contentTintColor = Palette.error
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = Palette.error.withAlphaComponent(0.10).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = Palette.error.withAlphaComponent(0.25).cgColor
        }
        restartCoreButton.target = self
        restartCoreButton.action = #selector(restartCoreClicked)
        restartCoreButton.toolTip = "停止当前恢复计时并重新启动 Core"
        viewCoreLogButton.target = self
        viewCoreLogButton.action = #selector(viewCoreLogClicked)
        viewCoreLogButton.toolTip = "打开 Core 最近日志"
        coreActions.translatesAutoresizingMaskIntoConstraints = false
        coreActions.orientation = .horizontal
        coreActions.spacing = 5
        coreActions.addArrangedSubview(restartCoreButton)
        coreActions.addArrangedSubview(viewCoreLogButton)
        coreActions.isHidden = true
        [coreStatus, modelStatus, agentStatus].forEach { field in
            field.wantsLayer = true
            field.layer?.cornerRadius = 11
            field.layer?.backgroundColor = Palette.canvas.withAlphaComponent(0.34).cgColor
            field.layer?.borderWidth = 1
            field.layer?.borderColor = Palette.border.withAlphaComponent(0.55).cgColor
            field.alignment = .center
            field.setContentHuggingPriority(.required, for: .horizontal)
        }
        [version, coreStatus, local, modelStatus, coreActions, agentStatus, monitor].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            version.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            version.centerYAnchor.constraint(equalTo: centerYAnchor),
            coreStatus.leadingAnchor.constraint(equalTo: version.trailingAnchor, constant: 28),
            coreStatus.centerYAnchor.constraint(equalTo: centerYAnchor),
            coreStatus.heightAnchor.constraint(equalToConstant: 24),
            local.leadingAnchor.constraint(equalTo: coreStatus.trailingAnchor, constant: 8),
            local.centerYAnchor.constraint(equalTo: centerYAnchor),
            local.heightAnchor.constraint(equalToConstant: 24),
            modelStatus.leadingAnchor.constraint(equalTo: local.trailingAnchor, constant: 8),
            modelStatus.centerYAnchor.constraint(equalTo: centerYAnchor),
            modelStatus.heightAnchor.constraint(equalToConstant: 24),
            coreActions.leadingAnchor.constraint(equalTo: modelStatus.trailingAnchor, constant: 8),
            coreActions.centerYAnchor.constraint(equalTo: centerYAnchor),
            coreActions.heightAnchor.constraint(equalToConstant: 24),
            restartCoreButton.heightAnchor.constraint(equalToConstant: 24),
            viewCoreLogButton.heightAnchor.constraint(equalToConstant: 24),
            agentStatus.trailingAnchor.constraint(equalTo: monitor.leadingAnchor, constant: -16),
            agentStatus.centerYAnchor.constraint(equalTo: centerYAnchor),
            agentStatus.heightAnchor.constraint(equalToConstant: 24),
            monitor.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            monitor.centerYAnchor.constraint(equalTo: centerYAnchor),
            monitor.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    func setAgentStatus(_ text: String, color: NSColor) {
        agentStatus.stringValue = (text.localizedCaseInsensitiveContains("idle") || text.contains("空闲") ? "○  " : "●  ") + text
        agentStatus.textColor = color
        agentStatus.layer?.borderColor = color.withAlphaComponent(0.22).cgColor
        agentStatus.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
    }

    func setModelStatus(_ text: String, color: NSColor) {
        modelStatus.stringValue = "●  " + text
        modelStatus.textColor = color
        modelStatus.layer?.borderColor = color.withAlphaComponent(0.22).cgColor
        modelStatus.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
    }

    func setCoreStatus(_ text: String, color: NSColor) {
        coreStatus.stringValue = "●  " + text
        coreStatus.textColor = color
        coreStatus.layer?.borderColor = color.withAlphaComponent(0.22).cgColor
        coreStatus.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        let actionable = text.contains("断开") || text.contains("失败") || text.contains("无法")
        coreActions.isHidden = !actionable
        restartCoreButton.isEnabled = actionable
        viewCoreLogButton.isEnabled = actionable
    }

    @objc private func restartCoreClicked() { onRestartCore?() }
    @objc private func viewCoreLogClicked() { onViewCoreLog?() }

    private func capsule(_ text: String, color: NSColor) -> NSTextField {
        let field = label(text, size: 10.5, weight: .medium, color: color)
        field.wantsLayer = true
        field.layer?.cornerRadius = 11
        field.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = color.withAlphaComponent(0.18).cgColor
        field.alignment = .center
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }
}

final class HoverButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    var normalColor: NSColor = .clear
    var hoverColor: NSColor = Palette.subtle

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalColor.cgColor
    }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

func symbol(_ name: String, size: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
}

func label(
    _ text: String,
    size: CGFloat = 13,
    weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return field
}

// MARK: - 本地数据

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

// MARK: - 桌面端状态模型

enum ModelState: String {
    case ready
    case missingKey = "missing_key"
    case unauthorized
    case rateLimited = "rate_limited"
    case offline
    case configurationError = "configuration_error"
}

enum AgentState: String {
    case idle
    case planning
    case running
    case testing
    case reviewing
    case completed
    case failed
    case cancelled
}

enum WorkspaceState: String {
    case ready
    case scanning
    case gitDirty = "git_dirty"
    case missing
    case error
}

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var role: MessageRole
    var content: String
    var createdAt = Date()
    var toolID: String? = nil
    var toolStatus: String? = nil
}

struct ChatSession: Codable, Identifiable {
    var id = UUID()
    var backendSessionID = UUID().uuidString.lowercased()
    var title = "新任务"
    var projectPath: String
    var messages: [ChatMessage] = []
    var backendCreated = false
    var createdAt = Date()
    var updatedAt = Date()
}

final class SessionStore {
    static let shared = SessionStore()

    private(set) var sessions: [ChatSession] = []
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Nexus", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("desktop-sessions.json")
        load()
    }

    func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder.nexus.decode([ChatSession].self, from: data)
        else {
            sessions = []
            return
        }
        sessions = decoded.map { stored in
            var session = stored
            session.messages.removeAll { message in
                let emptyAssistant = message.role == .assistant
                    && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let collision = message.role == .system
                    && message.content.localizedCaseInsensitiveContains("Session ID")
                    && message.content.localizedCaseInsensitiveContains("already in use")
                return emptyAssistant || collision
            }
            // Older builds could persist a generic cancellation card before
            // the more actionable model/API error arrived. Collapse that
            // stale card on load so existing sessions are repaired as well
            // as newly-created failures.
            let hasModelError = session.messages.contains { message in
                guard message.role == .system else { return false }
                let text = message.content.lowercased()
                return text.contains("api 配置")
                    || text.contains("api key")
                    || text.contains("密钥")
                    || text.contains("unauthorized")
                    || text.contains("401")
            }
            if hasModelError {
                session.messages.removeAll { message in
                    guard message.role == .system else { return false }
                    let text = message.content.lowercased()
                    return text.contains("任务已停止")
                        || text.contains("已取消")
                        || text.contains("cancel")
                }
            }
            return session
        }.sorted { $0.updatedAt > $1.updatedAt }
        save()
    }

    func save() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder.nexus.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func create(projectPath: String) -> ChatSession {
        let session = ChatSession(projectPath: projectPath)
        sessions.insert(session, at: 0)
        save()
        return session
    }

    func update(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        save()
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }
}

extension JSONEncoder {
    static var nexus: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var nexus: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - 配置

/// 使用 macOS 钥匙串保存桌面端凭据。服务名和账户名固定，升级 App 或迁移
/// 到外置磁盘后仍能找到同一项；任何错误都只返回状态，不把密钥写入日志。
enum SecureCredentialStore {
    private static let service = "com.ai-dev-one.nexus.api-key"
    private static let account = "openai-coding"
    private static let cacheLock = NSLock()
    private static var cachedValue: String?
    private static var didRead = false
    private static var loadInFlight = false
    private static var completionDelivered = false
    private static var lastReadStatus: OSStatus = errSecSuccess
    private static var currentState: CredentialLoadState = .loadingCredentials

    static var loadState: CredentialLoadState {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return currentState
    }

    private static var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        cacheLock.lock()
        if didRead || loadInFlight {
            let value = cachedValue
            cacheLock.unlock()
            return value
        }
        cacheLock.unlock()
        // Security.framework can wait for a login-keychain interaction. Never
        // perform that potentially blocking operation on AppKit's main thread.
        guard !Thread.isMainThread else { return nil }
        return readBlocking()
    }

    static func warmup(completion: (() -> Void)? = nil) {
        load(timeout: 2.5) { _ in completion?() }
    }

    /// Cold-start credential loading is bounded. A login-keychain/securityd
    /// stall may outlive this call, but it can never block AppKit or trigger a
    /// second prompt; the renderer receives a stable error state instead.
    static func load(
        timeout: TimeInterval = 2.5,
        completion: @escaping (CredentialLoadState) -> Void
    ) {
        cacheLock.lock()
        if didRead {
            let value = cachedValue
            let state: CredentialLoadState = value == nil ? .credentialsMissing : .credentialsReady
            currentState = state
            cacheLock.unlock()
            DispatchQueue.main.async { completion(state) }
            return
        }
        guard !loadInFlight else {
            cacheLock.unlock()
            return
        }
        loadInFlight = true
        completionDelivered = false
        currentState = .loadingCredentials
        cacheLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let value = readBlocking()
            cacheLock.lock()
            loadInFlight = false
            let status = lastReadStatus
            let state: CredentialLoadState
            if value != nil {
                state = .credentialsReady
            } else if status == errSecAuthFailed || status == errSecInteractionNotAllowed || status == errSecUserCanceled {
                state = .credentialsDenied
            } else {
                state = .credentialsMissing
            }
            currentState = state
            // A slow first Keychain read may legitimately finish after the
            // bounded timeout callback has already exposed credentials_error.
            // A late successful read is authoritative and must refresh the UI
            // once instead of leaving the renderer in that transient state.
            let lateSuccess = value != nil && completionDelivered
            let shouldDeliver = !completionDelivered || lateSuccess
            if shouldDeliver { completionDelivered = true }
            cacheLock.unlock()
            guard shouldDeliver else { return }
            DispatchQueue.main.async { completion(state) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, timeout)) {
            cacheLock.lock()
            guard loadInFlight, !completionDelivered else {
                cacheLock.unlock()
                return
            }
            completionDelivered = true
            currentState = .credentialsError
            cacheLock.unlock()
            completion(.credentialsError)
        }
    }

    private static func readBlocking() -> String? {
        cacheLock.lock()
        if didRead {
            let value = cachedValue
            cacheLock.unlock()
            return value
        }
        cacheLock.unlock()
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // 桌面启动不能弹出钥匙串授权对话框或卡住主线程；若当前登录会话
        // 无法无交互读取，则立即回退到环境变量/设置页，而不是白屏。
        query[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        cacheLock.lock()
        lastReadStatus = status
        cacheLock.unlock()
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cacheLock.lock()
            cachedValue = nil
            didRead = true
            cacheLock.unlock()
            return nil
        }
        cacheLock.lock()
        cachedValue = value
        didRead = true
        cacheLock.unlock()
        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            throw NSError(
                domain: "NexusCredentialStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "接口密钥不能为空或包含换行。"]
            )
        }
        let data = Data(trimmed.utf8)
        var updateQuery = identity
        updateQuery[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        let updateStatus = SecItemUpdate(
            updateQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            cacheLock.lock()
            cachedValue = trimmed
            didRead = true
            currentState = .credentialsReady
            cacheLock.unlock()
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(status: updateStatus)
        }

        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(status: addStatus)
        }
        cacheLock.lock()
        cachedValue = trimmed
        didRead = true
        currentState = .credentialsReady
        cacheLock.unlock()
    }

    static func delete() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status: status)
        }
        cacheLock.lock()
        cachedValue = nil
        didRead = true
        currentState = .credentialsMissing
        cacheLock.unlock()
    }

    private static func keychainError(status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "无法访问 macOS 钥匙串（错误码 \(status)）。"]
        )
    }

    private static func nonInteractiveAuthenticationContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}

final class NexusConfiguration {
    static let shared = NexusConfiguration()

    let homeURL: URL
    let configURL: URL

    private init() {
        homeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nexus", isDirectory: true)
        configURL = homeURL.appendingPathComponent("config.toml")
    }

    var hasAPIKey: Bool {
        if SecureCredentialStore.read() != nil {
            return true
        }
        if let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return legacyAPIKey() != nil
    }

    func hardenPermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: homeURL.path)
        if FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
    }

    /// 仅用于一次性迁移旧版本写入 TOML 的密钥；成功后会从配置中删除明文。
    func migrateLegacyAPIKeyIfNeeded() {
        guard let legacy = legacyAPIKey() else {
            SecureCredentialStore.warmup()
            return
        }
        // 迁移放到后台，钥匙串不可用或等待登录时也不会阻塞 AppKit 启动。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try SecureCredentialStore.save(legacy)
                DispatchQueue.main.async {
                    try? self?.removePlaintextAPIKey()
                }
            } catch {
                // 钥匙串不可用时保留旧值作为兼容回退，但不向日志输出任何凭据。
            }
        }
    }

    func removePlaintextAPIKey() throws {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        var inside = false
        var removed = false
        let filtered = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[model.openai-coding]" {
                inside = true
            } else if trimmed.hasPrefix("[") {
                inside = false
            }
            if inside, trimmed.hasPrefix("api_key"), trimmed.contains("=") {
                removed = true
                return false
            }
            return true
        }
        guard removed else { return }
        try filtered.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func legacyAPIKey() -> String? {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        var inOpenAI = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[model.openai-coding]" {
                inOpenAI = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inOpenAI = false
            }
            if inOpenAI, trimmed.hasPrefix("api_key"), trimmed.contains("=") {
                let value = trimmed.split(separator: "=", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var unquoted = value
                if unquoted.hasPrefix("\"") && unquoted.hasSuffix("\"") && unquoted.count >= 2 {
                    unquoted.removeFirst()
                    unquoted.removeLast()
                }
                return unquoted != "\"\"" && !unquoted.isEmpty ? unquoted : nil
            }
        }
        return nil
    }

    func value(named key: String, inSection section: String) -> String? {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        var inside = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[\(section)]" {
                inside = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inside = false
            }
            guard inside, trimmed.hasPrefix("\(key)"), let equal = trimmed.firstIndex(of: "=") else {
                continue
            }
            var value = trimmed[trimmed.index(after: equal)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            return value
        }
        return nil
    }

    func ensureOpenAIConfig() throws {
        try FileManager.default.createDirectory(
            at: homeURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: homeURL.path)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        let preset = Bundle.main.bundleURL
            .appendingPathComponent("Contents/config/presets/openai.toml")
        if FileManager.default.fileExists(atPath: preset.path) {
            try FileManager.default.copyItem(at: preset, to: configURL)
        } else {
            let initial = """
            [models]
            default = "openai-coding"

            [model.openai-coding]
            model = "deepseek-v4-flash"
            base_url = "https://api.deepseek.com"
            name = "DeepSeek 编码模型"
            description = "使用 DeepSeek OpenAI-compatible API"
            api_backend = "chat_completions"
            env_key = "OPENAI_API_KEY"
            """
            try initial.write(to: configURL, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    func updateOpenAI(model: String, baseURL: String) throws {
        try ensureOpenAIConfig()
        let safeModel = try validateTOMLValue(model, fieldName: "模型")
        let safeURL = try validateTOMLValue(baseURL, fieldName: "接口地址")
        var lines = try String(contentsOf: configURL, encoding: .utf8)
            .components(separatedBy: .newlines)
        var inside = false
        var modelWritten = false
        var urlWritten = false
        var backendWritten = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[model.openai-coding]" {
                inside = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inside = false
            }
            guard inside else { continue }
            if trimmed.hasPrefix("model"), trimmed.contains("=") {
                lines[index] = "model = \"\(safeModel)\""
                modelWritten = true
            } else if trimmed.hasPrefix("base_url"), trimmed.contains("=") {
                lines[index] = "base_url = \"\(safeURL)\""
                urlWritten = true
            } else if trimmed.hasPrefix("api_backend"), trimmed.contains("=") {
                let backend = safeURL.localizedCaseInsensitiveContains("api.openai.com")
                    ? "responses"
                    : "chat_completions"
                lines[index] = "api_backend = \"\(backend)\""
                backendWritten = true
            }
        }
        guard modelWritten, urlWritten, backendWritten else {
            throw NSError(
                domain: "NexusConfiguration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "模型配置不完整，请重新安装 AI Dev One。"]
            )
        }
        // OpenAI-compatible 中转站通常只提供当前编码模型；如果辅助任务
        // 继续沿用内置 grok-4.5，会在新会话启动/生成标题时产生误导性的
        // “密钥无效”错误。保存设置时让辅助任务跟随当前可用模型，避免
        // 用户每次改完中转地址后还要手动编辑 TOML。
        synchronizeAuxiliaryModels(in: &lines, model: safeModel)
        let output = lines.joined(separator: "\n")
        try output.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func synchronizeAuxiliaryModels(in lines: inout [String], model: String) {
        let keys = ["session_summary", "image_description"]
        guard let sectionStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[models]"
        }) else {
            lines.insert(contentsOf: [
                "[models]",
                "session_summary = \"\(model)\"",
                "image_description = \"\(model)\"",
                "",
            ], at: 0)
            return
        }

        let sectionEnd = lines[(sectionStart + 1)...].firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("[")
        }) ?? lines.endIndex
        var updated = Set<String>()
        for index in (sectionStart + 1)..<sectionEnd {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            for key in keys where trimmed.hasPrefix("\(key)") && trimmed.contains("=") {
                lines[index] = "\(key) = \"\(model)\""
                updated.insert(key)
            }
        }

        let missing = keys.filter { !updated.contains($0) }
        if !missing.isEmpty {
            lines.insert(contentsOf: missing.map { "\($0) = \"\(model)\"" }, at: sectionEnd)
        }
    }

    private func validateTOMLValue(_ value: String, fieldName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("\"") || trimmed.contains("\\")
            || trimmed.contains("\n") || trimmed.contains("\r") {
            throw NSError(
                domain: "NexusConfiguration",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldName)不能为空，也不能包含引号、反斜杠或换行。"]
            )
        }
        return trimmed
    }
}

enum BackendLocator {
    /// 任务执行不应依赖外置盘上的大体积二进制。安装器会把运行时复制到
    /// 本机 Application Support；如果旧版本尚未复制，则继续安全回退到
    /// 本地缓存、应用包资源和兼容路径。
    static var localRuntimeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Dev One/Runtime", isDirectory: true)
    }

    static var localRuntimeWrapperURL: URL {
        localRuntimeDirectory.appendingPathComponent("nexus")
    }

    static var localRuntimeBinaryURL: URL {
        localRuntimeDirectory.appendingPathComponent("nexus-agent")
    }

    private static func isUsableExecutable(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    static var wrapperURL: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("nexus")
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/nexus")
        let candidates = [localRuntimeWrapperURL, local, bundled, URL(fileURLWithPath: "/usr/local/bin/nexus")]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static var bundledBinaryURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("nexus-agent")
    }

    static var preferredBinaryURL: URL? {
        let homeCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/nexus/target/release/nexus-agent")
        let candidates = [
            localRuntimeBinaryURL,
            homeCache,
            bundledBinaryURL,
        ]
        return candidates.compactMap { $0 }.first(where: isUsableExecutable)
    }

    static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NEXUS_HOME"] = NexusConfiguration.shared.homeURL.path
        environment["GROK_HOME"] = NexusConfiguration.shared.homeURL.path
        environment["GROK_DISABLE_AUTOUPDATER"] = "1"
        environment["GROK_TELEMETRY_ENABLED"] = "0"
        environment["GROK_TELEMETRY_TRACE_UPLOAD"] = "0"
        environment["DISABLE_TELEMETRY"] = "1"
        // Finder-launched apps receive a minimal PATH. Re-add the toolchains
        // installed by the one-click installer so project commands such as
        // `npm test`, `cargo test`, and `python` do not fail merely because
        // the user did not launch the app from a shell. Missing directories
        // are ignored; the user's existing PATH remains the fallback.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let toolchainBins = [
            home.appendingPathComponent("Library/Application Support/AI Dev One Installer/toolchains/node/bin"),
            home.appendingPathComponent("Library/Application Support/AI Dev One Installer/toolchains/cargo/bin"),
            localRuntimeDirectory.appendingPathComponent("toolchains/node/bin"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let injectedPath = toolchainBins.map(\.path).joined(separator: ":")
        environment["PATH"] = injectedPath.isEmpty ? existingPath : injectedPath + ":" + existingPath
        // 桌面端优先从钥匙串注入凭据；外部环境变量仍可用于临时调试，
        // 但绝不把密钥作为命令行参数传递给代理。
        if (environment["OPENAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let key = SecureCredentialStore.read() {
            environment["OPENAI_API_KEY"] = key
        }
        if let baseURL = NexusConfiguration.shared.value(
            named: "base_url",
            inSection: "model.openai-coding"
        ), !baseURL.localizedCaseInsensitiveContains("api.openai.com"),
           environment["GROK_MAX_RETRIES"] == nil {
            // 中转站常把不可用模型返回为 502/503；避免 UI 长时间等待无效重试。
            environment["GROK_MAX_RETRIES"] = "1"
        }
        if let binary = preferredBinaryURL {
            environment["NEXUS_BIN"] = binary.path
        }
        return environment
    }
}

// MARK: - 后端执行

enum RunnerEvent {
    case coreState(CoreState)
    case text(String)
    case thought(String)
    case tool(id: String, title: String, status: String, detail: String?)
    case plan(String)
    case ended(sessionID: String?)
    case failed(String, cancellationSource: TaskCancellationSource? = nil)
}

enum TaskApproval: Equatable {
    case allowWorkspace
    case readOnly
}

/// 唯一的 Core 生命周期所有者。
///
/// 任务流仍由现有 Rust/ACP runtime 执行；本类只负责桌面端进程引用、退出
/// 分类、健康检查、有限退避和手动重启，避免 View/Controller 各自 spawn Core。
final class CoreSupervisor {
    private var process: Process?
    private var launchInFlight = false
    private var healthCheckInFlight = false
    private let parsingQueue = DispatchQueue(label: "cn.nexus.desktop.stream")
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var streamedError = ""
    private var reachedEnd = false
    private var stopRequested = false
    private var stopRequestedSource: TaskCancellationSource?
    private var manualShutdown = false
    private var generation: UInt64 = 0
    private var recoveryWorkItem: DispatchWorkItem?
    private var stableResetWorkItem: DispatchWorkItem?
    private var manualRestartInFlight = false
    private(set) var restartAttempt = 0
    private(set) var lastPID: Int32?
    private(set) var lastExitCode: Int32?
    private(set) var lastError: String?
    private(set) var state: CoreState = .stopped

    var isRunning: Bool { process?.isRunning == true || launchInFlight }

    private static let retryDelays: [TimeInterval] = [1, 2, 5]

    static var logFileURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AI Dev One", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("core-supervisor.log")
    }

    private func log(_ message: String) {
        let safe = redactSensitive(message).replacingOccurrences(of: "\n", with: " ")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(safe)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: Self.logFileURL.path),
           let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: Self.logFileURL, options: .atomic)
        }
    }

    private func emit(_ state: CoreState, event: ((RunnerEvent) -> Void)? = nil) {
        self.state = state
        log("state=\(state.rawValue)")
        if let event { event(.coreState(state)) }
    }

    /// Schedules a bounded health-check recovery. It never resends the old
    /// prompt: the interrupted transaction remains interrupted and the user
    /// chooses whether to rerun or roll back.
    func scheduleAutomaticRecovery(onState: @escaping (CoreState) -> Void) {
        guard !manualShutdown else { return }
        guard !manualRestartInFlight, !healthCheckInFlight, recoveryWorkItem == nil else { return }
        guard restartAttempt < Self.retryDelays.count else {
            emit(.failed)
            onState(.failed)
            log("automatic recovery exhausted")
            return
        }

        restartAttempt += 1
        let attempt = restartAttempt
        let delay = Self.retryDelays[attempt - 1]
        emit(.restarting)
        onState(.restarting)
        log("schedule restart attempt=\(attempt) delay=\(delay)s")

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recoveryWorkItem = nil
            guard !self.manualShutdown else { return }
            self.startHealthCheck(onState: onState, automaticAttempt: attempt)
        }
        recoveryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// A user-visible, single-flight restart. It is deliberately separate
    /// from automatic recovery so repeated clicks cannot spawn duplicate Core
    /// processes.
    func manualRestart(onState: @escaping (CoreState) -> Void) {
        guard !manualRestartInFlight else { return }
        manualRestartInFlight = true
        manualShutdown = false
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        stableResetWorkItem?.cancel()
        stableResetWorkItem = nil
        restartAttempt = 0
        generation &+= 1
        let old = process
        process = nil
        launchInFlight = false
        healthCheckInFlight = false
        if let old, old.isRunning { old.terminate() }
        emit(.starting)
        onState(.starting)
        log("manual restart requested")
        startHealthCheck(onState: { [weak self] state in
            guard let self else { return }
            if state == .ready || state == .failed { self.manualRestartInFlight = false }
            onState(state)
        }, automaticAttempt: nil)
    }

    /// Called for Cmd+Q/window close. This flag makes termination handlers
    /// inert with respect to recovery, preventing an exit→spawn loop.
    func shutdown() {
        manualShutdown = true
        generation &+= 1
        recoveryWorkItem?.cancel()
        stableResetWorkItem?.cancel()
        recoveryWorkItem = nil
        stableResetWorkItem = nil
        restartAttempt = 0
        stopRequested = true
        stopRequestedSource = .appShutdown
        let old = process
        process = nil
        launchInFlight = false
        healthCheckInFlight = false
        if let old, old.isRunning { old.terminate() }
        emit(.stopped)
        log("shutdown")
    }

    private func startHealthCheck(
        onState: @escaping (CoreState) -> Void,
        automaticAttempt: Int?
    ) {
        guard !manualShutdown, !healthCheckInFlight, process == nil,
              let executable = BackendLocator.wrapperURL else {
            manualRestartInFlight = false
            emit(.failed)
            onState(.failed)
            log("health check unavailable: wrapper missing")
            return
        }
        let token = generation
        let task = Process()
        task.executableURL = executable
        task.arguments = ["--version"]
        task.environment = BackendLocator.processEnvironment()
        let output = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = output
        task.standardError = errorPipe
        healthCheckInFlight = true
        process = task
        lastPID = task.processIdentifier
        emit(.starting)
        onState(.starting)
        log("health check spawn attempt=\(automaticAttempt.map(String.init) ?? "manual")")
        task.terminationHandler = { [weak self] finished in
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.healthCheckInFlight = false
                self.process = nil
                self.lastExitCode = finished.terminationStatus
                let ok = finished.terminationReason == .exit && finished.terminationStatus == 0
                if ok {
                    self.manualRestartInFlight = false
                    self.emit(.ready)
                    onState(.ready)
                    self.log("health check passed pid=\(self.lastPID.map(String.init) ?? "unknown")")
                    self.stableResetWorkItem?.cancel()
                    let reset = DispatchWorkItem { [weak self] in self?.restartAttempt = 0 }
                    self.stableResetWorkItem = reset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: reset)
                } else if self.manualRestartInFlight {
                    self.manualRestartInFlight = false
                    self.lastError = stderr.isEmpty ? "Core health check failed" : self.redactSensitive(stderr)
                    self.emit(.failed)
                    onState(.failed)
                    self.log("manual health check failed exit=\(finished.terminationStatus)")
                } else {
                    self.lastError = stderr.isEmpty ? "Core health check failed" : self.redactSensitive(stderr)
                    self.log("automatic health check failed exit=\(finished.terminationStatus)")
                    self.scheduleAutomaticRecovery(onState: onState)
                }
            }
        }
        do {
            try task.run()
            lastPID = task.processIdentifier
            log("health check started pid=\(task.processIdentifier)")
        } catch {
            healthCheckInFlight = false
            process = nil
            manualRestartInFlight = false
            lastError = error.localizedDescription
            emit(.failed)
            onState(.failed)
            log("health check spawn error: \(error.localizedDescription)")
        }
    }

    func send(
        prompt: String,
        session: ChatSession,
        approval: TaskApproval,
        event: @escaping (RunnerEvent) -> Void
    ) {
        // A terminated Process object can remain assigned briefly while its
        // termination handler drains the pipes. Treat it as reusable instead
        // of silently dropping the next approved task.
        guard !isRunning else { return }
        process = nil
        manualShutdown = false
        generation &+= 1
        let taskGeneration = generation
        guard let executable = BackendLocator.wrapperURL else {
            emit(.failed)
            event(.failed("没有找到 Nexus 编码代理。请重新运行一键安装。", cancellationSource: nil))
            return
        }

        let task = Process()
        task.executableURL = executable
        stopRequested = false
        stopRequestedSource = nil
        emit(.starting, event: event)
        // The read-only profile also disables network access on macOS. That
        // unintentionally prevented the model request itself from reaching
        // DeepSeek, so an “仅分析” task failed before it could read a file.
        // Plan mode is the write guard for this path; keep the workspace
        // sandbox so model/API traffic is available while edits remain
        // disallowed by the runtime's plan permission mode.
        let sandbox = "workspace"
        // A task that the user explicitly approved is a full workspace task.
        // `acceptEdits` still leaves unknown shell/network commands behind an
        // interactive permission prompt. The desktop renderer has no stdin
        // prompt loop, so those safe-but-unclassified commands would be
        // cancelled immediately (the UI then showed only “执行失败”). Use
        // the runtime's bypass mode for this explicit approval; the Rust
        // policy engine and the command-line deny rules remain active, so
        // destructive commands are still rejected before execution.
        let permissionMode = approval == .readOnly ? "plan" : "bypassPermissions"
        var arguments = [
            "run",
            "-p", prompt,
            "--output-format", "streaming-json",
            "--cwd", session.projectPath,
            "--sandbox", sandbox,
            "--permission-mode", permissionMode,
        ]
        if approval == .allowWorkspace {
            arguments.append("--always-approve")
        }
        // Keep the existing Rust policy engine as the execution boundary, but
        // make the high-risk deny list explicit for every desktop task. This
        // prevents a prompt or model instruction from silently widening it.
        arguments.append(contentsOf: NexusPolicyRules.commandLineArguments)
        if session.backendCreated {
            arguments.append(contentsOf: ["--resume", session.backendSessionID])
        } else {
            arguments.append(contentsOf: ["--session-id", session.backendSessionID])
        }
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: session.projectPath, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        stdoutBuffer = ""
        stderrBuffer = ""
        streamedError = ""
        reachedEnd = false

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.consumeStdout(text, event: event)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.parsingQueue.async {
                self?.stderrBuffer += text
            }
        }
        task.terminationHandler = { [weak self] finished in
            guard let self else { return }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let remainingOut = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let remainingErr = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            self.parsingQueue.async {
                if !remainingOut.isEmpty {
                    self.stdoutBuffer += remainingOut
                    self.flushCompleteLines(event: event, includeRemainder: true)
                }
                self.stderrBuffer += remainingErr
                let didEnd = self.reachedEnd
                let rawError = [self.streamedError, self.stderrBuffer]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let errorText = self.localizedError(rawError)
                let sessionCollision = rawError.localizedCaseInsensitiveContains("session id")
                    && rawError.localizedCaseInsensitiveContains("already in use")
                DispatchQueue.main.async {
                    // A manual shutdown or a newer task may have replaced
                    // this Process. Its termination handler must not mutate
                    // the current Core state or schedule another restart.
                    guard self.generation == taskGeneration else { return }
                    self.launchInFlight = false
                    if self.process === finished { self.process = nil }
                    self.lastPID = finished.processIdentifier
                    self.lastExitCode = finished.terminationStatus
                    if sessionCollision && !session.backendCreated {
                        var resumed = session
                        resumed.backendCreated = true
                        self.send(
                            prompt: prompt,
                            session: resumed,
                            approval: approval,
                            event: event
                        )
                        return
                    }
                    if !didEnd {
                        if self.stopRequested {
                            self.emit(.stopped)
                            event(.failed("任务已停止。", cancellationSource: self.stopRequestedSource ?? .unknown))
                        } else if finished.terminationReason == .uncaughtSignal {
                            // Signal termination is a Core disconnect even if
                            // the child emitted stderr while being killed.
                            // Classify it before ordinary API/tool errors.
                            self.emit(.disconnected, event: event)
                        } else if !errorText.isEmpty {
                            event(.failed(errorText.isEmpty ? "Nexus 运行失败，请检查设置后重试。" : errorText, cancellationSource: nil))
                        } else if finished.terminationStatus != 0 {
                            event(.failed("Nexus 运行失败，请检查模型设置后重试。", cancellationSource: nil))
                        } else {
                            self.emit(.ready)
                            event(.ended(sessionID: nil))
                        }
                    }
                }
            }
        }

        // Process.run() can block while macOS resolves an executable on an
        // external volume. Never run it on the AppKit thread: the approval
        // dialog must close immediately and show "正在启动 Core" instead of
        // making the whole window appear frozen.
        launchInFlight = true
        process = task
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                task.environment = BackendLocator.processEnvironment()
                try task.run()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.launchInFlight = false
                    // The termination handler may have already cleared this
                    // reference for a very short-lived process. Do not report
                    // a false "ready" state after an immediate launch failure.
                    guard task.isRunning else {
                        if self.process === task { self.process = nil }
                        return
                    }
                    if self.process == nil { self.process = task }
                    self.lastPID = task.processIdentifier
                    self.emit(.ready, event: event)
                    self.stableResetWorkItem?.cancel()
                    let reset = DispatchWorkItem { [weak self] in self?.restartAttempt = 0 }
                    self.stableResetWorkItem = reset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: reset)
                }
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.generation == taskGeneration else { return }
                    self.launchInFlight = false
                    self.process = nil
                    self.lastError = error.localizedDescription
                    self.emit(.failed)
                    event(.failed("无法启动 Nexus：\(error.localizedDescription)", cancellationSource: nil))
                }
            }
        }
    }

    func stop(source: TaskCancellationSource = .user) {
        guard let task = process else { return }
        stopRequested = true
        stopRequestedSource = source
        guard task.isRunning else { return }
        task.interrupt()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            if task.isRunning {
                task.terminate()
            }
        }
    }

    private func consumeStdout(_ text: String, event: @escaping (RunnerEvent) -> Void) {
        parsingQueue.async { [weak self] in
            guard let self else { return }
            self.stdoutBuffer += text
            self.flushCompleteLines(event: event, includeRemainder: false)
        }
    }

    private func flushCompleteLines(
        event: @escaping (RunnerEvent) -> Void,
        includeRemainder: Bool
    ) {
        var lines = stdoutBuffer.components(separatedBy: .newlines)
        if includeRemainder {
            stdoutBuffer = ""
        } else {
            stdoutBuffer = lines.removeLast()
        }
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parse(line: line, event: event)
        }
        if includeRemainder,
           !stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parse(line: stdoutBuffer, event: event)
            stdoutBuffer = ""
        }
    }

    private func parse(line: String, event: @escaping (RunnerEvent) -> Void) {
        guard
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        let callback: RunnerEvent?
        switch type {
        case "text":
            callback = .text(json["data"] as? String ?? "")
        case "thought":
            callback = .thought(json["data"] as? String ?? "")
        case "tool_start", "tool_update":
            callback = .tool(
                id: json["id"] as? String ?? UUID().uuidString,
                title: json["title"] as? String ?? "执行工具",
                status: json["status"] as? String ?? (type == "tool_start" ? "running" : "updated"),
                detail: toolDetail(from: json)
            )
        case "plan":
            if let value = json["data"],
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
               let text = String(data: data, encoding: .utf8) {
                callback = .plan(text)
            } else {
                callback = .plan("计划已更新")
            }
        case "end":
            reachedEnd = true
            callback = .ended(sessionID: json["sessionId"] as? String)
        case "error":
            streamedError = json["message"] as? String ?? ""
            callback = nil
        case "auto_compact_started":
            callback = .thought("正在整理较长的会话…")
        case "auto_compact_completed":
            callback = .thought("会话整理完成，正在继续…")
        default:
            callback = nil
        }
        if let callback {
            DispatchQueue.main.async { event(callback) }
        }
    }

    /// Extract the human-readable failure detail from streaming-json tool
    /// updates. The upstream format puts it in a nested `content` array; the
    /// old parser discarded it and left the desktop with a vague “执行工具”.
    private func toolDetail(from json: [String: Any]) -> String? {
        for key in ["error", "message", "detail"] {
            if let value = json[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return redactSensitive(value)
            }
        }
        guard let content = json["content"] as? [[String: Any]] else { return nil }
        let texts = content.compactMap { item -> String? in
            if let text = item["text"] as? String { return text }
            if let nested = item["content"] as? [String: Any],
               let text = nested["text"] as? String { return text }
            return nil
        }
        let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : redactSensitive(joined)
    }

    private func localizedError(_ raw: String) -> String {
        let text = redactSensitive(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.isEmpty { return "" }
        let lowered = text.lowercased()
        if lowered.contains("reqwest error stream")
            || lowered.contains("error sending request")
            || lowered.contains("ssl connection")
            || lowered.contains("connection reset")
            || lowered.contains("connection refused")
            || lowered.contains("could not resolve host") {
            return "连接中转接口失败，可能是网络或 TLS 暂时不稳定，请重试。"
        }
        if lowered.contains("authentication required")
            || lowered.contains("credentials were rejected")
            || lowered.contains("unauthorized")
            || lowered.contains("invalid api key")
            || lowered.contains("incorrect api key")
            || lowered.contains("401") {
            return "DeepSeek 接口拒绝了当前密钥。请打开“设置”，更新有效密钥后重试。"
        }
        if lowered.contains("rate limit") || lowered.contains("429") {
            return "请求过于频繁或账户额度不足，请稍后重试并检查 DeepSeek 账户额度。"
        }
        if lowered.contains("no available channel") || lowered.contains("model_not_found") {
            return "当前接口没有可用的模型通道。请在“设置”中检查模型名称、账户额度和余额。"
        }
        if lowered.contains("bad_response_status_code") || lowered.contains("502") || lowered.contains("503") {
            return "模型接口暂时无法转发请求（HTTP 502/503）。请检查模型名称、账户余额和接口协议。"
        }
        if lowered.contains("not found") && lowered.contains("model") {
            return "当前模型不可用，请在“设置”中检查模型名称。"
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "连接接口超时，请检查网络后重试。"
        }
        if lowered.contains("couldn't create session") && lowered.contains("not found") {
            return "无法恢复这个任务的代理会话，请新建任务后重试。"
        }
        let last = text.components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
        return "Nexus 运行失败：\(last)"
    }

    private func redactSensitive(_ value: String) -> String {
        var result = value
        let patterns = [
            (#"(?i)sk-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
            (#"(?i)xai-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+\-/=]+"#, "$1<redacted-key>"),
            (#"(?i)(api[_-]?key\s*[=:]\s*)[^\s,&]+"#, "$1<redacted-key>"),
        ]
        for (pattern, replacement) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }
        return result
    }
}

/// 兼容旧的 Controller/test 引用；生命周期实现统一在 CoreSupervisor。
typealias NexusRunner = CoreSupervisor

// MARK: - 输入框

final class ComposerTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let returnPressed = event.keyCode == 36 || event.keyCode == 76
        if returnPressed,
           !event.modifierFlags.contains(.shift),
           !hasMarkedText() {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }
}

final class ComposerView: LayerView, NSTextViewDelegate {
    let textView = ComposerTextView()
    let sendButton = NSButton(frame: .zero)
    let placeholder = label("输入任务…  ⌘Enter 发送", size: 14, color: Palette.secondaryText)
    let projectHint = label("输入任务…  ⌘Enter 发送", size: 11, color: Palette.secondaryText)
    private let toolStack = NSStackView()
    private let sendGradient = CAGradientLayer()

    var onSend: (() -> Void)?
    var onStop: (() -> Void)?
    private(set) var running = false
    private var configurationRequired = false

    init() {
        super.init(fillColor: Palette.elevated.withAlphaComponent(0.78), cornerRadius: 20, strokeColor: Palette.border)
        translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        textView.frame = NSRect(x: 0, y: 0, width: 480, height: 46)
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.minSize = NSSize(width: 0, height: 46)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 480,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = self
        textView.onSend = { [weak self] in self?.submit() }
        scroll.documentView = textView

        placeholder.translatesAutoresizingMaskIntoConstraints = false

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isBordered = false
        sendButton.image = symbol("arrow.up", size: 14, weight: .semibold)
        sendButton.imagePosition = .imageOnly
        sendButton.contentTintColor = .white
        sendButton.wantsLayer = true
        sendButton.layer?.backgroundColor = Palette.accent.cgColor
        sendButton.layer?.cornerRadius = 17
        sendGradient.colors = [Palette.accent.cgColor, Palette.blue.cgColor]
        sendGradient.startPoint = CGPoint(x: 0, y: 0)
        sendGradient.endPoint = CGPoint(x: 1, y: 1)
        sendGradient.cornerRadius = 17
        sendButton.layer?.addSublayer(sendGradient)
        sendButton.target = self
        sendButton.action = #selector(sendClicked)
        sendButton.toolTip = "发送"

        projectHint.translatesAutoresizingMaskIntoConstraints = false
        projectHint.maximumNumberOfLines = 1
        projectHint.lineBreakMode = .byTruncatingMiddle

        addSubview(scroll)
        addSubview(placeholder)
        addSubview(sendButton)
        addSubview(projectHint)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -52),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scroll.heightAnchor.constraint(equalToConstant: 51),

            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            placeholder.topAnchor.constraint(equalTo: topAnchor, constant: 18),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.topAnchor.constraint(equalTo: topAnchor, constant: 76),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),

            projectHint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 188),
            projectHint.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),
            projectHint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            projectHint.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 120),
        ])

        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolStack.orientation = .horizontal
        toolStack.spacing = 6
        toolStack.alignment = .centerY
        ["plus", "chevron.left.forwardslash.chevron.right", "photo", "paperclip", "mic"].forEach { imageName in
            let button = NSButton(frame: .zero)
            button.isBordered = false
            button.image = symbol(imageName, size: 13, weight: .medium)
            button.imagePosition = .imageOnly
            button.contentTintColor = Palette.secondaryText
            button.wantsLayer = true
            button.layer?.cornerRadius = 14
            button.layer?.backgroundColor = Palette.canvas.withAlphaComponent(0.34).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = Palette.border.withAlphaComponent(0.7).cgColor
            button.translatesAutoresizingMaskIntoConstraints = false
            toolStack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
        addSubview(toolStack)
        NSLayoutConstraint.activate([
            toolStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func layout() {
        super.layout()
        sendGradient.frame = sendButton.bounds
    }

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            placeholder.isHidden = !newValue.isEmpty
        }
    }

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !textView.string.isEmpty
    }

    func textDidBeginEditing(_ notification: Notification) {
        layer?.borderColor = Palette.accent.withAlphaComponent(0.72).cgColor
        layer?.shadowColor = Palette.accent.withAlphaComponent(0.45).cgColor
        layer?.shadowOpacity = 0.64
        layer?.shadowRadius = 26
    }

    func textDidEndEditing(_ notification: Notification) {
        layer?.borderColor = Palette.border.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.52).cgColor
        layer?.shadowOpacity = 0.42
        layer?.shadowRadius = 18
    }

    func setRunning(_ value: Bool) {
        running = value
        textView.isEditable = !value && !configurationRequired
        sendButton.isEnabled = value || !configurationRequired
        sendButton.image = symbol(value ? "stop.fill" : "arrow.up", size: 13, weight: .semibold)
        sendButton.toolTip = value ? "停止任务" : "发送"
        sendButton.layer?.backgroundColor = (
            value ? NSColor.systemRed : Palette.accent
        ).cgColor
    }

    func setModelConfigured(_ configured: Bool) {
        configurationRequired = !configured
        placeholder.stringValue = configured ? "输入任务…  ⌘Enter 发送" : "请先完成模型配置"
        placeholder.textColor = configured ? Palette.secondaryText : Palette.warning
        textView.isEditable = configured && !running
        sendButton.isEnabled = configured || running
        sendButton.toolTip = configured ? (running ? "停止任务" : "发送") : "请先完成模型配置"
        if !configured { textView.string = "" }
        placeholder.isHidden = !textView.string.isEmpty
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    private func submit() {
        if running {
            onStop?()
        } else if !configurationRequired,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onSend?()
        }
    }

    @objc private func sendClicked() {
        submit()
    }
}

// MARK: - 侧边栏

final class SessionCellView: NSTableCellView {
    let titleLabel = label("", size: 13, weight: .medium)
    let detailLabel = label("", size: 11, color: Palette.secondaryText)
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = symbol("leaf.fill", size: 14)
        iconView.contentTintColor = Palette.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }
}

final class SessionRowView: NSTableRowView {
    private var isHovered = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, selectionHighlightStyle == .none else { return }
        Palette.accent.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 7, yRadius: 7).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 7, yRadius: 7)
        Palette.selected.setFill()
        path.fill()
        Palette.accent.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1
        path.stroke()
        Palette.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 9, width: 2, height: max(12, bounds.height - 18)), xRadius: 1, yRadius: 1).fill()
    }
}

final class SidebarView: LayerView, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = NSTableView()
    private let searchField = NSSearchField()
    private var allSessions: [ChatSession] = []
    private(set) var sessions: [ChatSession] = [] {
        didSet { tableView.reloadData() }
    }
    var allSessionsValue: [ChatSession] {
        get { allSessions }
        set {
            allSessions = newValue
            applySearch()
        }
    }
    var onNewTask: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onSettings: (() -> Void)?
    var onEcosystem: (() -> Void)?
    var onDelete: ((UUID) -> Void)?

    init() {
        super.init(fillColor: Palette.sidebar, cornerRadius: 14, strokeColor: Palette.border)
        translatesAutoresizingMaskIntoConstraints = false

        let logo = LayerView(fillColor: Palette.accent.withAlphaComponent(0.14), cornerRadius: 9, strokeColor: Palette.accent.withAlphaComponent(0.6))
        logo.translatesAutoresizingMaskIntoConstraints = false
        let logoLeaf = NSImageView()
        logoLeaf.translatesAutoresizingMaskIntoConstraints = false
        logoLeaf.image = symbol("leaf.fill", size: 15, weight: .medium)
        logoLeaf.contentTintColor = Palette.accent
        logo.addSubview(logoLeaf)
        logoLeaf.pinEdges(to: logo, insets: NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))

        let product = label("AI Dev One", size: 15, weight: .semibold)
        product.translatesAutoresizingMaskIntoConstraints = false
        let route = label("Route 2", size: 10.5, color: Palette.secondaryText)
        route.translatesAutoresizingMaskIntoConstraints = false

        let newTask = HoverButton(title: "  新建会话", target: self, action: #selector(newTaskClicked))
        newTask.translatesAutoresizingMaskIntoConstraints = false
        newTask.isBordered = false
        newTask.alignment = .left
        newTask.font = .systemFont(ofSize: 12.5, weight: .medium)
        newTask.image = symbol("plus", size: 13, weight: .semibold)
        newTask.imagePosition = .imageLeading
        newTask.wantsLayer = true
        newTask.layer?.cornerRadius = 7
        newTask.normalColor = Palette.elevated.withAlphaComponent(0.5)
        newTask.hoverColor = Palette.subtle
        newTask.layer?.backgroundColor = newTask.normalColor.cgColor
        newTask.layer?.borderWidth = 1
        newTask.layer?.borderColor = Palette.border.cgColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索 Session  ⌘K"
        searchField.font = .systemFont(ofSize: 12)
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let section = label("SESSION", size: 10, weight: .semibold, color: Palette.secondaryText)
        section.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(selectionChanged)
        tableView.menu = makeContextMenu()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let settings = HoverButton(title: "  设置", target: self, action: #selector(settingsClicked))
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.isBordered = false
        settings.alignment = .left
        settings.font = .systemFont(ofSize: 13)
        settings.image = symbol("gearshape", size: 14)
        settings.imagePosition = .imageLeading
        settings.wantsLayer = true
        settings.layer?.cornerRadius = 7
        settings.hoverColor = Palette.subtle

        let ecosystem = HoverButton(title: "  生态与工具", target: self, action: #selector(ecosystemClicked))
        ecosystem.translatesAutoresizingMaskIntoConstraints = false
        ecosystem.isBordered = false
        ecosystem.alignment = .left
        ecosystem.font = .systemFont(ofSize: 13)
        ecosystem.image = symbol("puzzlepiece.extension", size: 14)
        ecosystem.imagePosition = .imageLeading
        ecosystem.wantsLayer = true
        ecosystem.layer?.cornerRadius = 7
        ecosystem.hoverColor = Palette.subtle

        addSubview(logo)
        addSubview(product)
        addSubview(route)
        addSubview(newTask)
        addSubview(searchField)
        addSubview(section)
        addSubview(scroll)
        addSubview(ecosystem)
        addSubview(settings)

        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            logo.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            logo.widthAnchor.constraint(equalToConstant: 28),
            logo.heightAnchor.constraint(equalToConstant: 28),
            product.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 9),
            product.topAnchor.constraint(equalTo: logo.topAnchor, constant: 1),
            route.leadingAnchor.constraint(equalTo: product.leadingAnchor),
            route.topAnchor.constraint(equalTo: product.bottomAnchor, constant: 2),

            newTask.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            newTask.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            newTask.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 16),
            newTask.heightAnchor.constraint(equalToConstant: 34),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: newTask.bottomAnchor, constant: 7),
            searchField.heightAnchor.constraint(equalToConstant: 26),

            section.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            section.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: section.bottomAnchor, constant: 7),
            scroll.bottomAnchor.constraint(equalTo: ecosystem.topAnchor, constant: -8),

            ecosystem.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            ecosystem.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            ecosystem.bottomAnchor.constraint(equalTo: settings.topAnchor, constant: -3),
            ecosystem.heightAnchor.constraint(equalToConstant: 34),

            settings.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            settings.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            settings.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            settings.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sessions.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SessionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SessionCellView()
        let session = sessions[row]
        cell.titleLabel.stringValue = session.title
        cell.detailLabel.stringValue = URL(fileURLWithPath: session.projectPath).lastPathComponent
        cell.titleLabel.maximumNumberOfLines = 1
        cell.detailLabel.maximumNumberOfLines = 1
        return cell
    }

    func select(id: UUID?) {
        guard let id, let index = sessions.firstIndex(where: { $0.id == id }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    func clearSearch() {
        guard !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        applySearch()
    }

    @objc private func newTaskClicked() {
        onNewTask?()
    }

    @objc private func searchChanged() {
        applySearch()
    }

    private func applySearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if query.isEmpty {
            sessions = allSessions
            return
        }
        sessions = allSessions.filter { session in
            let searchable = [
                session.title,
                URL(fileURLWithPath: session.projectPath).lastPathComponent,
                session.projectPath,
                session.messages.last?.content ?? "",
            ]
            return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @objc private func selectionChanged() {
        let row = tableView.selectedRow
        guard sessions.indices.contains(row) else { return }
        onSelect?(sessions[row].id)
    }

    @objc private func settingsClicked() {
        onSettings?()
    }

    @objc private func ecosystemClicked() {
        onEcosystem?()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "删除任务", action: #selector(deleteSelected), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteSelected() {
        let clicked = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard sessions.indices.contains(clicked) else { return }
        onDelete?(sessions[clicked].id)
    }
}

// MARK: - Agent 时间线与对话内容

final class AgentTimelineView: LayerView {
    private var cards: [(container: LayerView, dot: NSTextField, title: NSTextField, detail: NSTextField)] = []
    private var lastActiveIndex = 0

    init() {
        super.init(fillColor: Palette.elevated.withAlphaComponent(0.24), cornerRadius: 12, strokeColor: Palette.border.withAlphaComponent(0.70))
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        [("Architect", "Planning architecture", Palette.accent),
         ("Builder", "Editing project", Palette.violet),
         ("Verifier", "Running tests", Palette.success),
         ("Reviewer", "Code review", Palette.blue)]
            .forEach { titleText, detailText, color in
                let card = LayerView(fillColor: Palette.canvas.withAlphaComponent(0.28), cornerRadius: 9, strokeColor: Palette.border.withAlphaComponent(0.40))
                let dot = label("●", size: 9, weight: .bold, color: color.withAlphaComponent(0.58))
                let title = label(titleText, size: 10.5, weight: .semibold, color: NSColor(calibratedWhite: 0.90, alpha: 0.88))
                let detail = label(detailText, size: 9, color: Palette.secondaryText)
                [dot, title, detail].forEach {
                    $0.translatesAutoresizingMaskIntoConstraints = false
                    card.addSubview($0)
                }
                NSLayoutConstraint.activate([
                    dot.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                    dot.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                    dot.widthAnchor.constraint(equalToConstant: 10),
                    title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
                    title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
                    title.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
                    detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                    detail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
                    detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
                ])
                stack.addArrangedSubview(card)
                cards.append((card, dot, title, detail))
            }
        setStage("Idle")
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    func setStage(_ stage: String) {
        let lowered = stage.lowercased()
        let completedAll = lowered.contains("completed") || lowered.contains("完成")
        let activeIndex: Int
        if lowered.contains("architect") || lowered.contains("plan") || lowered.contains("think") { activeIndex = 0 }
        else if lowered.contains("builder") || lowered.contains("edit") { activeIndex = 1 }
        else if lowered.contains("verif") || lowered.contains("test") || lowered.contains("run") { activeIndex = 2 }
        else if lowered.contains("review") || lowered.contains("read") || lowered.contains("search") { activeIndex = 3 }
        else { activeIndex = -1 }
        if activeIndex >= 0 { lastActiveIndex = activeIndex }
        updateCards(activeIndex: activeIndex, completedAll: completedAll, failed: false)
    }

    func setFailure() {
        updateCards(activeIndex: lastActiveIndex, completedAll: false, failed: true)
    }

    private func updateCards(activeIndex: Int, completedAll: Bool, failed: Bool) {
        let runningDetails = [
            "Planning architecture",
            "Editing project",
            "Running tests",
            "Code review",
        ]

        for (index, card) in cards.enumerated() {
            let failedCard = failed && index == activeIndex
            let active = !failed && index == activeIndex
            let completed = !failed && (completedAll || (activeIndex >= 0 && index < activeIndex))
            card.container.fillColor = failedCard
                ? Palette.error.withAlphaComponent(0.12)
                : active
                ? Palette.selected.withAlphaComponent(0.72)
                : completed ? Palette.success.withAlphaComponent(0.11)
                : Palette.canvas.withAlphaComponent(0.22)
            card.container.strokeColor = failedCard
                ? Palette.error.withAlphaComponent(0.55)
                : active
                ? Palette.accent.withAlphaComponent(0.62)
                : completed ? Palette.success.withAlphaComponent(0.40)
                : Palette.border.withAlphaComponent(0.34)
            card.container.layer?.shadowColor = failedCard ? Palette.error.cgColor : active ? Palette.accent.cgColor : Palette.success.cgColor
            card.container.layer?.shadowOpacity = failedCard ? 0.18 : active ? 0.22 : (completed ? 0.08 : 0)
            card.container.layer?.shadowRadius = failedCard || active ? 12 : 6
            card.dot.textColor = failedCard ? Palette.error : active ? Palette.accent : completed ? Palette.success : Palette.secondaryText.withAlphaComponent(0.50)
            card.title.textColor = failedCard || active || completed ? NSColor(calibratedWhite: 0.95, alpha: 1) : NSColor(calibratedWhite: 0.82, alpha: 0.78)
            card.detail.stringValue = failedCard ? "Failed" : completed ? "Completed" : active ? runningDetails[index] : "Waiting"
            card.detail.textColor = failedCard ? Palette.error.withAlphaComponent(0.90) : active ? Palette.accent.withAlphaComponent(0.90) : completed ? Palette.success.withAlphaComponent(0.85) : Palette.secondaryText.withAlphaComponent(0.70)
        }
    }
}

final class ChatContentView: LayerView {
    let headerTitle = label("新任务", size: 17, weight: .semibold, color: NSColor(calibratedWhite: 0.95, alpha: 1))
    let projectButton = HoverButton(frame: .zero)
    let statusLabel = label("○ Agent Idle", size: 11, weight: .medium, color: Palette.secondaryText)
    let changesButton = HoverButton(frame: .zero)
    let terminalButton = HoverButton(frame: .zero)
    let composer = ComposerView()
    let timeline = AgentTimelineView()

    private let messageStack = NSStackView()
    private let scrollView = NSScrollView()
    private let scrollDocument = LayerView(fillColor: .clear)
    private var activeAssistantLabel: NSTextField?
    private var emptyState: NSView?

    var onProject: (() -> Void)?
    var onShowWorkspace: ((Int) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?

    init() {
        super.init(fillColor: Palette.canvas.withAlphaComponent(0.32), cornerRadius: 14, strokeColor: Palette.border)
        translatesAutoresizingMaskIntoConstraints = false

        let header = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.30))
        header.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.translatesAutoresizingMaskIntoConstraints = false

        projectButton.translatesAutoresizingMaskIntoConstraints = false
        projectButton.isBordered = false
        projectButton.font = .systemFont(ofSize: 11)
        projectButton.contentTintColor = Palette.secondaryText
        projectButton.image = symbol("folder", size: 11)
        projectButton.imagePosition = .imageLeading
        projectButton.wantsLayer = true
        projectButton.layer?.cornerRadius = 6
        projectButton.hoverColor = Palette.subtle
        projectButton.target = self
        projectButton.action = #selector(projectClicked)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        configureHeaderButton(
            changesButton,
            title: " 编辑",
            image: "pencil",
            action: #selector(showChanges)
        )
        configureHeaderButton(
            terminalButton,
            title: " 更多",
            image: "ellipsis",
            action: #selector(showTerminal)
        )

        let separator = LayerView(fillColor: Palette.border)
        separator.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(headerTitle)
        header.addSubview(projectButton)
        header.addSubview(changesButton)
        header.addSubview(terminalButton)
        header.addSubview(statusLabel)
        header.addSubview(separator)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        scrollDocument.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = scrollDocument

        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.orientation = .vertical
        messageStack.alignment = .centerX
        messageStack.spacing = 18
        messageStack.distribution = .gravityAreas
        scrollDocument.addSubview(messageStack)

        composer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(timeline)
        addSubview(scrollView)
        addSubview(composer)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 72),
            headerTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: changesButton.leadingAnchor, constant: -14),
            headerTitle.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            projectButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 17),
            projectButton.trailingAnchor.constraint(lessThanOrEqualTo: changesButton.leadingAnchor, constant: -14),
            projectButton.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 1),
            projectButton.heightAnchor.constraint(equalToConstant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22),
            statusLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            terminalButton.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -15),
            terminalButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            terminalButton.widthAnchor.constraint(equalToConstant: 58),
            terminalButton.heightAnchor.constraint(equalToConstant: 28),
            changesButton.trailingAnchor.constraint(equalTo: terminalButton.leadingAnchor, constant: -3),
            changesButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            changesButton.widthAnchor.constraint(equalToConstant: 58),
            changesButton.heightAnchor.constraint(equalToConstant: 28),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            timeline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            timeline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            timeline.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            timeline.heightAnchor.constraint(equalToConstant: 50),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: timeline.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -18),

            scrollDocument.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            scrollDocument.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            scrollDocument.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            scrollDocument.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            scrollDocument.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),

            messageStack.leadingAnchor.constraint(equalTo: scrollDocument.leadingAnchor, constant: 34),
            messageStack.trailingAnchor.constraint(equalTo: scrollDocument.trailingAnchor, constant: -34),
            messageStack.topAnchor.constraint(equalTo: scrollDocument.topAnchor, constant: 28),
            messageStack.bottomAnchor.constraint(equalTo: scrollDocument.bottomAnchor, constant: -28),

            composer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            composer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            composer.centerXAnchor.constraint(equalTo: centerXAnchor),
            composer.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            composer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    func display(session: ChatSession, streamingMessageID: UUID? = nil) {
        headerTitle.stringValue = session.title
        let folder = URL(fileURLWithPath: session.projectPath).lastPathComponent
        projectButton.title = "  \(folder)"
        projectButton.toolTip = session.projectPath
        composer.projectHint.stringValue = "当前项目：\(session.projectPath)"
        composer.projectHint.toolTip = session.projectPath
        activeAssistantLabel = nil
        clearMessages()

        if session.messages.isEmpty {
            showEmptyState(projectName: folder)
        } else {
            for message in session.messages {
                addMessage(message, isStreaming: message.id == streamingMessageID)
            }
            scrollToBottom(animated: false)
        }
    }

    func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    func setAgentStage(_ stage: String) {
        if stage.lowercased().contains("fail") || stage.contains("失败") {
            timeline.setFailure()
        } else {
            timeline.setStage(stage)
        }
    }

    func addMessage(_ message: ChatMessage, isStreaming: Bool = false) {
        removeEmptyState()
        let row = LayerView(fillColor: .clear)
        row.translatesAutoresizingMaskIntoConstraints = false
        let bubble: LayerView
        let textField = NSTextField(wrappingLabelWithString: message.content)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = message.role == .system
            ? .systemFont(ofSize: 12)
            : .systemFont(ofSize: 14)
        textField.textColor = message.role == .system ? Palette.warning : NSColor(calibratedWhite: 0.9, alpha: 0.95)
        textField.isSelectable = true
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        switch message.role {
        case .user:
            bubble = LayerView(fillColor: Palette.accent.withAlphaComponent(0.16), cornerRadius: 14, strokeColor: Palette.accent.withAlphaComponent(0.2))
            bubble.addSubview(textField)
            row.addSubview(bubble)
            bubble.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.76),
                textField.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
                textField.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
                textField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
                textField.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
            ])
        case .assistant:
            bubble = LayerView(fillColor: .clear)
            let avatar = LayerView(fillColor: Palette.accent.withAlphaComponent(0.13), cornerRadius: 16, strokeColor: Palette.accent.withAlphaComponent(0.7))
            avatar.translatesAutoresizingMaskIntoConstraints = false
            let avatarIcon = NSImageView()
            avatarIcon.translatesAutoresizingMaskIntoConstraints = false
            avatarIcon.image = symbol("leaf.fill", size: 14, weight: .medium)
            avatarIcon.contentTintColor = Palette.accent
            avatar.addSubview(avatarIcon)
            avatarIcon.pinEdges(to: avatar, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
            bubble.addSubview(avatar)
            bubble.addSubview(textField)
            row.addSubview(bubble)
            bubble.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                avatar.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
                avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 1),
                avatar.widthAnchor.constraint(equalToConstant: 25),
                avatar.heightAnchor.constraint(equalToConstant: 25),
                textField.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
                textField.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
                textField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 3),
                textField.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            ])
            if isStreaming {
                activeAssistantLabel = textField
                if textField.stringValue.isEmpty {
                    textField.stringValue = "Thinking…"
                }
            }
        case .system:
            if message.content.localizedCaseInsensitiveContains("密钥")
                || message.content.localizedCaseInsensitiveContains("api key")
                || message.content.localizedCaseInsensitiveContains("配置") {
                textField.stringValue = "API 配置异常\n" + message.content
            }
            textField.maximumNumberOfLines = 3
            textField.lineBreakMode = .byTruncatingTail
            bubble = LayerView(fillColor: Palette.error.withAlphaComponent(0.08), cornerRadius: 11, strokeColor: Palette.error.withAlphaComponent(0.20))
            row.addSubview(bubble)
            bubble.translatesAutoresizingMaskIntoConstraints = false
            let actionStack = NSStackView()
            actionStack.translatesAutoresizingMaskIntoConstraints = false
            actionStack.orientation = .horizontal
            actionStack.spacing = 8
            let settingsButton = NSButton(title: "打开模型设置", target: self, action: #selector(openErrorSettings))
            settingsButton.bezelStyle = .texturedRounded
            settingsButton.font = .systemFont(ofSize: 11, weight: .medium)
            settingsButton.contentTintColor = Palette.accent
            settingsButton.toolTip = "打开设置更新模型和 API Key"
            let retryButton = NSButton(title: "重新连接", target: self, action: #selector(retryError))
            retryButton.bezelStyle = .texturedRounded
            retryButton.font = .systemFont(ofSize: 11, weight: .medium)
            retryButton.contentTintColor = Palette.secondaryText
            actionStack.addArrangedSubview(settingsButton)
            actionStack.addArrangedSubview(retryButton)
            let systemStack = NSStackView(views: [textField, actionStack])
            systemStack.translatesAutoresizingMaskIntoConstraints = false
            systemStack.orientation = .vertical
            systemStack.alignment = .leading
            systemStack.spacing = 5
            bubble.addSubview(systemStack)
            NSLayoutConstraint.activate([
                bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                systemStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 13),
                systemStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -13),
                systemStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7),
                systemStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
            ])
        case .tool:
            bubble = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.62), cornerRadius: 11, strokeColor: Palette.border)
            let toolIcon = NSImageView()
            toolIcon.translatesAutoresizingMaskIntoConstraints = false
            toolIcon.image = symbol("hammer", size: 13)
            toolIcon.contentTintColor = Palette.secondaryText
            bubble.addSubview(toolIcon)
            bubble.addSubview(textField)
            row.addSubview(bubble)
            bubble.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 12, weight: .medium)
            textField.textColor = Palette.secondaryText
            NSLayoutConstraint.activate([
                bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 36),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                toolIcon.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 11),
                toolIcon.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
                toolIcon.widthAnchor.constraint(equalToConstant: 16),
                toolIcon.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: toolIcon.trailingAnchor, constant: 7),
                textField.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
                textField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
                textField.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            ])
        }

        messageStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: messageStack.widthAnchor).isActive = true
        scrollToBottom(animated: true)
    }

    func updateStreamingText(_ text: String) {
        activeAssistantLabel?.stringValue = text.isEmpty ? "Thinking…" : text
        activeAssistantLabel?.invalidateIntrinsicContentSize()
        scrollToBottom(animated: false)
    }

    func finishStreaming() {
        activeAssistantLabel = nil
    }

    private func showEmptyState(projectName: String) {
        let container = LayerView(fillColor: .clear)
        container.translatesAutoresizingMaskIntoConstraints = false
        let icon = LayerView(fillColor: Palette.accent, cornerRadius: 15)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = symbol("leaf.fill", size: 22, weight: .medium)
        iconView.contentTintColor = Palette.accent
        icon.addSubview(iconView)
        iconView.pinEdges(to: icon, insets: NSEdgeInsets(top: 13, left: 13, bottom: 13, right: 13))

        let title = label("准备好一起构建了吗？", size: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = label(
            "描述你想在“\(projectName)”中完成的任务，AI Dev One 会阅读代码、编辑文件并运行命令。",
            size: 13,
            color: Palette.secondaryText
        )
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 0
        subtitle.lineBreakMode = .byWordWrapping

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(subtitle)
        messageStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: messageStack.widthAnchor).isActive = true
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 55),
            icon.widthAnchor.constraint(equalToConstant: 50),
            icon.heightAnchor.constraint(equalToConstant: 50),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 19),
            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])
        emptyState = container
    }

    private func clearMessages() {
        messageStack.arrangedSubviews.forEach {
            messageStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        emptyState = nil
    }

    private func removeEmptyState() {
        guard let emptyState else { return }
        messageStack.removeArrangedSubview(emptyState)
        emptyState.removeFromSuperview()
        self.emptyState = nil
    }

    private func scrollToBottom(animated: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollDocument.layoutSubtreeIfNeeded()
            let maxY = max(0, self.scrollDocument.bounds.height - self.scrollView.contentView.bounds.height)
            let point = NSPoint(x: 0, y: maxY)
            if animated {
                self.scrollView.contentView.animator().setBoundsOrigin(point)
            } else {
                self.scrollView.contentView.setBoundsOrigin(point)
            }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    @objc private func projectClicked() {
        onProject?()
    }

    private func configureHeaderButton(
        _ button: HoverButton,
        title: String,
        image: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = title
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.image = symbol(image, size: 12)
        button.imagePosition = .imageLeading
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.hoverColor = Palette.subtle
        button.target = self
        button.action = action
    }

    @objc private func showChanges() {
        onShowWorkspace?(0)
    }

    @objc private func showTerminal() {
        onShowWorkspace?(3)
    }

    @objc private func openErrorSettings() {
        onOpenSettings?()
    }

    @objc private func retryError() {
        onRetry?()
    }
}

// MARK: - 工作区面板

final class WorkspacePanelView: LayerView {
    private let segmented = NSSegmentedControl(
        labels: ["工作区", "文件", "知识库", "工具"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let projectName = label("AI Dev One Route 2", size: 13, weight: .medium)
    private let projectPathLabel = label("~/Projects/ai-dev-one-route2", size: 10.5, color: Palette.secondaryText)
    private let statsStack = NSStackView()
    private let recentTitle = label("最近变更", size: 11, weight: .semibold, color: Palette.secondaryText)
    private var statValueLabels: [NSTextField] = []
    private let outputView = NSTextView()
    private let commandField = NSTextField()
    private let actionButton = NSButton(title: "刷新", target: nil, action: nil)
    private let browserButton = NSButton(title: "浏览器验证", target: nil, action: nil)
    private let screenshotButton = NSButton(title: "查看截图", target: nil, action: nil)
    private let githubActions = NSStackView()
    private let githubCancelButton = NSButton(title: "停止等待", target: nil, action: nil)
    private let githubPRButton = NSButton(title: "查看 PR", target: nil, action: nil)
    private let summaryLabel = label("", size: 11, color: Palette.secondaryText)
    private let intelligence = ProjectIntelligenceService.shared
    private let githubProvider = GitHubCLIProvider()
    private var runningProcess: Process?
    private var screenshotWindow: NSWindow?
    private var latestIntelligence: ProjectIntelligenceOverview?
    private var intelligenceRequestID = UUID()
    private var githubActionsHeight: NSLayoutConstraint?
    private var githubSnapshot = GitHubWorkflowSnapshot.idle

    var projectPath: String = "" {
        didSet {
            // Invalidate any queued index/ecosystem callbacks before handling
            // an empty path or switching to another project.
            intelligenceRequestID = UUID()
            guard !projectPath.isEmpty else {
                intelligence.stopWatching()
                latestIntelligence = nil
                outputView.string = "尚未选择项目。"
                summaryLabel.stringValue = "尚未选择项目"
                return
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            projectPathLabel.stringValue = projectPath.hasPrefix(home)
                ? "~" + String(projectPath.dropFirst(home.count))
                : projectPath
            projectPathLabel.toolTip = projectPath
            projectName.toolTip = projectPath
            projectName.stringValue = URL(fileURLWithPath: projectPath).lastPathComponent.isEmpty
                ? "AI Dev One Route 2"
                : URL(fileURLWithPath: projectPath).lastPathComponent
            if !isHidden {
                refresh()
            }
            updateProjectStats()
            let requestID = intelligenceRequestID
            intelligence.startWatching(projectPath: projectPath) { [weak self] overview in
                guard let self, self.intelligenceRequestID == requestID else { return }
                self.latestIntelligence = overview
                if self.segmented.selectedSegment == 2 {
                    self.renderProjectIntelligence(overview)
                }
            }
            intelligence.index(projectPath: projectPath, force: false) { [weak self] overview in
                guard let self, self.intelligenceRequestID == requestID else { return }
                self.latestIntelligence = overview
                if self.segmented.selectedSegment == 2 {
                    self.renderProjectIntelligence(overview)
                }
            }
        }
    }
    var onClose: (() -> Void)?
    var onBrowserVerification: (() -> Void)?
    var onCancelGitHubTask: ((String) -> Void)?

    init() {
        super.init(fillColor: Palette.elevated.withAlphaComponent(0.38), cornerRadius: 14, strokeColor: Palette.border.withAlphaComponent(0.72))
        translatesAutoresizingMaskIntoConstraints = false

        let title = label("工作区", size: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let close = HoverButton(frame: .zero)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.isBordered = false
        close.image = symbol("xmark", size: 12, weight: .semibold)
        close.imagePosition = .imageOnly
        close.wantsLayer = true
        close.layer?.cornerRadius = 6
        close.hoverColor = Palette.subtle
        close.target = self
        close.action = #selector(closePanel)
        close.toolTip = "关闭工作区面板"

        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(segmentChanged)

        let projectCard = LayerView(fillColor: Palette.canvas.withAlphaComponent(0.42), cornerRadius: 12, strokeColor: Palette.border.withAlphaComponent(0.72))
        projectCard.translatesAutoresizingMaskIntoConstraints = false
        let folder = NSImageView()
        folder.translatesAutoresizingMaskIntoConstraints = false
        folder.image = symbol("folder", size: 15, weight: .medium)
        folder.contentTintColor = Palette.accent
        projectName.translatesAutoresizingMaskIntoConstraints = false
        projectPathLabel.translatesAutoresizingMaskIntoConstraints = false
        projectPathLabel.lineBreakMode = .byTruncatingMiddle
        let projectChevron = NSImageView()
        projectChevron.translatesAutoresizingMaskIntoConstraints = false
        projectChevron.image = symbol("chevron.down", size: 10, weight: .semibold)
        projectChevron.contentTintColor = Palette.secondaryText
        let projectStatus = label("● Ready", size: 9.5, weight: .medium, color: Palette.success)
        projectStatus.translatesAutoresizingMaskIntoConstraints = false
        [folder, projectName, projectPathLabel, projectStatus, projectChevron].forEach(projectCard.addSubview)
        NSLayoutConstraint.activate([
            folder.leadingAnchor.constraint(equalTo: projectCard.leadingAnchor, constant: 12),
            folder.centerYAnchor.constraint(equalTo: projectCard.centerYAnchor),
            folder.widthAnchor.constraint(equalToConstant: 22),
            folder.heightAnchor.constraint(equalToConstant: 22),
            projectName.leadingAnchor.constraint(equalTo: folder.trailingAnchor, constant: 10),
            projectName.topAnchor.constraint(equalTo: projectCard.topAnchor, constant: 10),
            projectName.trailingAnchor.constraint(lessThanOrEqualTo: projectStatus.leadingAnchor, constant: -8),
            projectPathLabel.leadingAnchor.constraint(equalTo: projectName.leadingAnchor),
            projectPathLabel.topAnchor.constraint(equalTo: projectName.bottomAnchor, constant: 3),
            projectPathLabel.trailingAnchor.constraint(lessThanOrEqualTo: projectStatus.leadingAnchor, constant: -8),
            projectStatus.trailingAnchor.constraint(equalTo: projectChevron.leadingAnchor, constant: -10),
            projectStatus.centerYAnchor.constraint(equalTo: projectCard.centerYAnchor),
            projectChevron.trailingAnchor.constraint(equalTo: projectCard.trailingAnchor, constant: -12),
            projectChevron.centerYAnchor.constraint(equalTo: projectCard.centerYAnchor),
            projectChevron.widthAnchor.constraint(equalToConstant: 14),
            projectChevron.heightAnchor.constraint(equalToConstant: 14),
        ])

        statsStack.translatesAutoresizingMaskIntoConstraints = false
        statsStack.orientation = .horizontal
        statsStack.spacing = 6
        statsStack.distribution = .fillEqually
        [("代码", "—", Palette.accent), ("测试", "—", Palette.blue),
         ("文档", "—", Palette.violet), ("变更", "—", NSColor(calibratedWhite: 0.9, alpha: 1))]
            .forEach { statTitle, value, color in
                let card = LayerView(fillColor: Palette.canvas.withAlphaComponent(0.30), cornerRadius: 9, strokeColor: Palette.border.withAlphaComponent(0.58))
                let valueLabel = label(value, size: 15, weight: .semibold, color: color)
                let titleLabel = label(statTitle, size: 9.5, color: Palette.secondaryText)
                [valueLabel, titleLabel].forEach {
                    $0.translatesAutoresizingMaskIntoConstraints = false
                    card.addSubview($0)
                }
                NSLayoutConstraint.activate([
                    valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
                    valueLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
                    titleLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
                    titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),
                    titleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
                ])
                statValueLabels.append(valueLabel)
                statsStack.addArrangedSubview(card)
            }

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        recentTitle.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        outputView.frame = NSRect(x: 0, y: 0, width: 360, height: 580)
        outputView.autoresizingMask = [.width]
        outputView.drawsBackground = false
        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.isRichText = true
        outputView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        outputView.textContainerInset = NSSize(width: 12, height: 12)
        outputView.textContainer?.widthTracksTextView = true
        outputView.isHorizontallyResizable = false
        outputView.isVerticallyResizable = true
        scroll.documentView = outputView

        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.placeholderString = "输入命令后按回车运行"
        commandField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        commandField.target = self
        commandField.action = #selector(primaryAction)
        commandField.isHidden = true

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(primaryAction)

        browserButton.translatesAutoresizingMaskIntoConstraints = false
        browserButton.bezelStyle = .rounded
        browserButton.target = self
        browserButton.action = #selector(browserVerificationClicked)
        browserButton.toolTip = "启动本地开发服务器并检查页面截图、Console、Network 与布局"
        browserButton.isHidden = true

        screenshotButton.translatesAutoresizingMaskIntoConstraints = false
        screenshotButton.bezelStyle = .rounded
        screenshotButton.target = self
        screenshotButton.action = #selector(browserScreenshotClicked)
        screenshotButton.toolTip = "打开最近一次浏览器验证截图"
        screenshotButton.isHidden = true

        githubActions.translatesAutoresizingMaskIntoConstraints = false
        githubActions.orientation = .horizontal
        githubActions.alignment = .centerY
        githubActions.distribution = .gravityAreas
        githubActions.spacing = 8
        githubCancelButton.bezelStyle = .rounded
        githubCancelButton.target = self
        githubCancelButton.action = #selector(cancelGitHubWorkflowClicked)
        githubCancelButton.toolTip = "停止 AI Dev One 的后续 CI 等待；不会关闭 PR 或取消 GitHub Actions"
        githubPRButton.bezelStyle = .rounded
        githubPRButton.target = self
        githubPRButton.action = #selector(viewGitHubPullRequestClicked)
        githubPRButton.toolTip = "在浏览器中查看远程 Pull Request"
        githubActions.addArrangedSubview(githubCancelButton)
        githubActions.addArrangedSubview(githubPRButton)
        githubActions.isHidden = true

        let separator = LayerView(fillColor: Palette.border)
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(close)
        addSubview(segmented)
        addSubview(projectCard)
        addSubview(statsStack)
        addSubview(recentTitle)
        addSubview(summaryLabel)
        addSubview(separator)
        addSubview(scroll)
        addSubview(commandField)
        addSubview(actionButton)
        addSubview(browserButton)
        addSubview(screenshotButton)
        addSubview(githubActions)

        let githubHeight = githubActions.heightAnchor.constraint(equalToConstant: 0)
        githubActionsHeight = githubHeight

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 26),
            close.heightAnchor.constraint(equalToConstant: 26),

            segmented.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            segmented.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            segmented.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 15),
            segmented.heightAnchor.constraint(equalToConstant: 30),

            projectCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            projectCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            projectCard.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 13),
            projectCard.heightAnchor.constraint(equalToConstant: 54),

            statsStack.leadingAnchor.constraint(equalTo: projectCard.leadingAnchor),
            statsStack.trailingAnchor.constraint(equalTo: projectCard.trailingAnchor),
            statsStack.topAnchor.constraint(equalTo: projectCard.bottomAnchor, constant: 11),
            statsStack.heightAnchor.constraint(equalToConstant: 52),

            recentTitle.leadingAnchor.constraint(equalTo: projectCard.leadingAnchor),
            recentTitle.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 15),

            summaryLabel.leadingAnchor.constraint(equalTo: projectCard.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: projectCard.trailingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: recentTitle.bottomAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 9),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: githubActions.topAnchor, constant: -8),

            githubActions.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            githubActions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            githubActions.bottomAnchor.constraint(equalTo: commandField.topAnchor, constant: -8),
            githubHeight,

            commandField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            commandField.trailingAnchor.constraint(equalTo: screenshotButton.leadingAnchor, constant: -8),
            commandField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            commandField.heightAnchor.constraint(equalToConstant: 28),
            screenshotButton.trailingAnchor.constraint(equalTo: browserButton.leadingAnchor, constant: -8),
            screenshotButton.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            screenshotButton.widthAnchor.constraint(equalToConstant: 70),
            screenshotButton.heightAnchor.constraint(equalToConstant: 28),
            browserButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            browserButton.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            browserButton.widthAnchor.constraint(equalToConstant: 88),
            browserButton.heightAnchor.constraint(equalToConstant: 28),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionButton.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 62),
            actionButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func layout() {
        super.layout()
        guard let scroll = outputView.enclosingScrollView else { return }
        let availableWidth = max(0, scroll.contentSize.width)
        if abs(outputView.frame.width - availableWidth) > 0.5 {
            outputView.setFrameSize(NSSize(
                width: availableWidth,
                height: max(outputView.frame.height, scroll.contentSize.height)
            ))
        }
    }

    func select(segment: Int) {
        segmented.selectedSegment = max(0, min(3, segment))
        updateMode()
        refresh()
    }

    func refresh() {
        guard !projectPath.isEmpty else {
            outputView.string = "尚未选择项目。"
            return
        }
        switch segmented.selectedSegment {
        case 0:
            loadChanges()
        case 1:
            loadFiles()
        case 2:
            loadEcosystem()
        default:
            showTools()
        }
    }

    func updateGitHubWorkflow(_ snapshot: GitHubWorkflowSnapshot) {
        githubSnapshot = snapshot
        if segmented.selectedSegment == 3 {
            updateMode()
            showTools()
        }
    }

    private func updateMode() {
        let terminal = segmented.selectedSegment == 3
        let extensions = segmented.selectedSegment == 2
        let hasGitHubTask = terminal && githubSnapshot.transaction?.github != nil
        commandField.isHidden = !(terminal || extensions)
        browserButton.isHidden = !terminal
        screenshotButton.isHidden = true
        githubActions.isHidden = !hasGitHubTask
        githubActionsHeight?.constant = hasGitHubTask ? 28 : 0
        githubCancelButton.isHidden = githubSnapshot.metadata?.workflowState != .waitingCI
            && githubSnapshot.metadata?.workflowState != .ciFailed
            && githubSnapshot.metadata?.workflowState != .repairingCI
        githubPRButton.isHidden = githubSnapshot.metadata?.pullRequestURL == nil
        commandField.placeholderString = terminal
            ? "输入命令后按回车运行；或点击浏览器验证"
            : "插件地址，或：mcp add 名称 URL"
        actionButton.title = terminal ? "运行" : (extensions ? "重新索引" : "刷新")
        summaryLabel.stringValue = [
            "查看当前 Git 工作区的文件改动",
            "浏览当前项目文件",
            "查看 MCP、插件与技能状态",
            "运行命令、测试与浏览器验证",
        ][segmented.selectedSegment]
    }

    private func loadChanges() {
        summaryLabel.stringValue = "正在读取 Git 更改…"
        runInBackground { [projectPath] in
            guard FileManager.default.fileExists(atPath: projectPath) else {
                DispatchQueue.main.async { [weak self] in
                    self?.summaryLabel.stringValue = "项目缺失"
                    self?.outputView.string = "当前项目目录不存在，请在聊天区重新选择项目。"
                    self?.scrollToTop()
                }
                return
            }
            let status = Self.run(
                executable: "/usr/bin/git",
                arguments: ["-C", projectPath, "status", "--short"]
            )
            let lines = status.output
                .split(separator: "\n")
                .map(String.init)
            let total = lines.count
            let visibleLines = Array(lines.prefix(50))
            let visibleRaw = visibleLines.joined(separator: "\n")
            let body: String
            if status.code != 0 {
                body = "当前目录不是 Git 仓库，或无法读取状态。\n\n\(Self.capped(status.output))"
            } else if total == 0 {
                body = "最近变更\n\n工作区没有未提交的更改。"
            } else {
                let entries = visibleLines.map { self.formattedChange($0, projectPath: projectPath) }
                let suffix = total > visibleLines.count
                    ? "\n\n还有 (total - visibleLines.count) 个文件未显示。"
                    : ""
                body = "最近变更\n\n" + entries.joined(separator: "\n\n") + suffix
            }
            DispatchQueue.main.async { [weak self] in
                self?.summaryLabel.stringValue = status.code != 0
                    ? "Git 工作区"
                    : "最近变更 · \(total) 个文件"
                if status.code == 0 && total > 0 {
                    self?.outputView.textStorage?.setAttributedString(
                        self?.renderChanges(visibleRaw, projectPath: projectPath, total: total) ?? NSAttributedString(string: body)
                    )
                } else {
                    self?.outputView.string = Self.capped(body)
                }
                self?.scrollToTop()
            }
        }
    }

    private func formattedChange(_ raw: String, projectPath: String) -> String {
        let code = raw.count >= 2 ? String(raw.prefix(2)) : raw
        let rawPath = raw.count > 3 ? String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces) : raw
        let path = rawPath.components(separatedBy: " -> ").last ?? rawPath
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        let relative = path.hasPrefix(projectPath + "/")
            ? String(path.dropFirst(projectPath.count + 1))
            : path
        let state: String
        let dot: String
        if code.contains("?") || code.contains("A") {
            state = "已添加"
            dot = "●"
        } else if code.contains("D") {
            state = "已删除"
            dot = "●"
        } else {
            state = "已修改"
            dot = "●"
        }
        return "\(dot)  \(name)  ·  \(state)\n    \(relative)"
    }

    private func renderChanges(_ raw: String, projectPath: String, total: Int) -> NSAttributedString {
        let visibleCount = raw.split(separator: "\n").count
        let result = NSMutableAttributedString(
            string: "最近变更\(total > visibleCount ? "（显示前 50 个）" : "")\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.92),
            ]
        )
        for item in raw.split(separator: "\n") {
            let source = String(item)
            let line = formattedChange(source, projectPath: projectPath)
            let attributed = NSMutableAttributedString(
                string: line + "\n\n",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                    .foregroundColor: Palette.secondaryText,
                ]
            )
            let statusColor: NSColor
            let code = source.count >= 2 ? String(source.prefix(2)) : source
            if code.contains("?") || code.contains("A") { statusColor = Palette.success }
            else if code.contains("D") { statusColor = Palette.error }
            else { statusColor = Palette.accent }
            let firstLineLength = (line as NSString).range(of: "\n").location
            attributed.addAttribute(.foregroundColor, value: statusColor, range: NSRange(location: 0, length: firstLineLength))
            result.append(attributed)
        }
        if total > visibleCount {
            result.append(NSAttributedString(
                string: "\n还有 \(total - visibleCount) 个文件未显示。",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: Palette.secondaryText,
                ]
            ))
        }
        return result
    }

    /// Prefer Git's indexed file list over a recursive filesystem walk. A
    /// Rust workspace can contain a very large `target/` tree on the external
    /// drive; scanning it for a small Workspace preview competes with task
    /// startup and makes the Send action appear stuck.
    private func projectFiles(_ projectPath: String) -> [String] {
        let tracked = Self.run(
            executable: "/usr/bin/git",
            arguments: ["-C", projectPath, "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
        )
        if tracked.code == 0 {
            return tracked.output
                .split(separator: "\0", omittingEmptySubsequences: true)
                .map { projectPath + "/" + String($0) }
        }
        let fallback = Self.run(
            executable: "/usr/bin/find",
            arguments: [
                projectPath,
                "-maxdepth", "5",
                "-type", "d",
                "(",
                "-path", "*/.git",
                "-o", "-path", "*/target",
                "-o", "-path", "*/dist",
                "-o", "-path", "*/node_modules",
                "-o", "-path", "*/.cache",
                ")",
                "-prune",
                "-o", "-type", "f", "-print",
            ]
        )
        return fallback.output.split(separator: "\n").map(String.init)
    }

    private func loadFiles() {
        summaryLabel.stringValue = "正在读取项目文件…"
        runInBackground { [projectPath] in
            let files = self.projectFiles(projectPath)
                .prefix(24)
                .map { path in
                    let url = URL(fileURLWithPath: path)
                    let relative = url.path.replacingOccurrences(of: projectPath + "/", with: "")
                    let icon = url.pathExtension == "swift" || url.pathExtension == "rs" ? "◈" : "□"
                    return icon + "  " + relative
                }
            let body = files.isEmpty
                ? "当前项目还没有可显示的文件。"
                : "项目文件\n\n" + files.joined(separator: "\n")
            DispatchQueue.main.async { [weak self] in
                self?.summaryLabel.stringValue = files.isEmpty ? "没有项目文件" : "显示前 24 个文件"
                self?.outputView.string = Self.capped(body)
                self?.scrollToTop()
            }
        }
    }

    private func updateProjectStats() {
        guard !projectPath.isEmpty, statValueLabels.count >= 4 else { return }
        runInBackground { [projectPath] in
            let paths = self.projectFiles(projectPath)
            var code = 0
            var tests = 0
            var docs = 0
            let changeResult = Self.run(executable: "/usr/bin/git", arguments: ["-C", projectPath, "status", "--short"])
            let changes = changeResult.output.split(separator: "\n").count
            for path in paths.prefix(500) {
                let url = URL(fileURLWithPath: path)
                let ext = url.pathExtension.lowercased()
                if ["rs", "swift", "ts", "tsx", "js", "jsx", "py", "go", "java", "c", "cpp", "h"].contains(ext) {
                    code += 1
                    if path.localizedCaseInsensitiveContains("test") || path.localizedCaseInsensitiveContains("spec") {
                        tests += 1
                    }
                } else if ["md", "mdx", "txt", "rst"].contains(ext) {
                    docs += 1
                }
            }
            let values = ["\(code)", "\(tests)", "\(docs)", "\(changes)"]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for (index, value) in values.enumerated() where index < self.statValueLabels.count {
                    self.statValueLabels[index].stringValue = value
                }
            }
        }
    }

    private func showTools() {
        summaryLabel.stringValue = "Agent 工具箱"
        let githubSection = githubToolsSection()
        outputView.string = """
        代码分析        扫描架构、依赖与潜在问题
        性能分析        采集构建与运行时性能
        测试运行        执行项目测试并汇总结果
        构建项目        在当前工作区运行构建命令
        Git 工具        查看、暂存与审查文件更改
        部署工具        连接发布流程与环境配置
        浏览器验证      启动本地页面，检查截图、Console、Network 与布局

        GitHub 自主工程
        \(githubRemoteRoleSummary())
        \(githubSection)
        Autonomous Mode 默认关闭
        远程策略        读取允许；Push / PR 需授权；合并、强推、删分支永久拒绝

        在底部输入命令，可直接在当前项目目录执行；点击右侧“浏览器验证”开始本地视觉验证。
        """
        githubProvider.authenticate { [weak self] result in
            guard let self, self.segmented.selectedSegment == 3 else { return }
            let status: String
            switch result {
            case .success(.githubReady): status = "● 已授权"
            case .success(.githubUnauthorized), .success(.githubNotConfigured): status = "○ 未授权"
            case .success(.githubAuthenticating): status = "○ 授权中"
            case .success(.githubError), .failure: status = "× 不可用"
            }
            self.outputView.string = self.outputView.string.replacingOccurrences(of: "连接状态        正在读取…", with: "连接状态        \(status)")
        }
        scrollToTop()
    }

    /// Keep the write target and read-only upstream visible at the point where
    /// a user reviews GitHub automation.  This is deliberately read-only: it
    /// never changes remotes and falls back to a neutral message when a project
    /// is not a Git repository or has not been bound yet.
    private func githubRemoteRoleSummary() -> String {
        guard !projectPath.isEmpty else {
            return "写入目标        origin · 未绑定\n只读上游        upstream · 未绑定"
        }

        func remoteLabel(_ name: String, fallback: String) -> String {
            let result = Self.run(executable: "/usr/bin/git", arguments: ["-C", projectPath, "remote", "get-url", name])
            guard result.code == 0 else { return fallback }
            let rawURL = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = GitHubRepositoryBindingResolver.parseGitHubURL(rawURL) {
                return "\(parsed.owner)/\(parsed.repo)"
            }
            return rawURL.isEmpty ? fallback : "已配置"
        }

        let origin = remoteLabel("origin", fallback: "未配置")
        let upstream = remoteLabel("upstream", fallback: "未配置")
        return "写入目标        origin · \(origin)\n只读上游        upstream · \(upstream)"
    }

    private func githubToolsSection() -> String {
        guard let transaction = githubSnapshot.transaction,
              let metadata = transaction.github else {
            return "连接状态        正在读取…\n任务状态        当前没有 GitHub 任务"
        }
        let repository = metadata.githubRepository?.fullName ?? "未绑定"
        let issue = metadata.issueNumber.map { "#\($0)" } ?? "—"
        let pullRequest = metadata.pullRequestNumber.map { "#\($0)" } ?? "—"
        let run = metadata.ciRunId.map { id in
            metadata.ciRunAttempt.map { "\(id) · attempt \($0)" } ?? id
        } ?? "等待首次读取"
        let ci: String
        switch metadata.ciLastObservedState ?? metadata.ciFinalState {
        case .queued: ci = "○ 排队中"
        case .inProgress: ci = "● 运行中"
        case .passed: ci = "● 已通过"
        case .failed, .timedOut: ci = "× 未通过"
        case .cancelled: ci = "○ GitHub CI 已取消"
        case .neutral, .skipped: ci = "○ 已跳过"
        case .unknown, .none: ci = "○ 等待状态"
        }
        let state: String
        if githubSnapshot.restoring {
            state = "正在恢复 GitHub 任务…"
        } else {
            switch metadata.workflowState {
            case .waitingCI: state = "正在等待 CI"
            case .ciFailed: state = "CI 未通过，可继续修复"
            case .readyForHumanMerge: state = "等待人工合并"
            case .cancelled: state = "已停止自动处理（远程 PR 仍然存在）"
            case .blocked: state = "任务已阻止"
            case .failed: state = "任务失败"
            case .interrupted: state = "任务已中断"
            default: state = metadata.workflowState.rawValue
            }
        }
        let error = githubSnapshot.error.map { "\n恢复提示        \($0)" } ?? ""
        return """
        连接状态        正在读取…
        Repository      \(repository)
        Issue           \(issue)
        Branch          \(metadata.taskBranch ?? "—")
        PR              \(pullRequest)
        CI              \(ci)
        Run             \(run)
        状态            \(state)\(error)
        """
    }

    func showBrowserVerificationStatus(_ text: String) {
        guard segmented.selectedSegment == 3 else { return }
        summaryLabel.stringValue = "浏览器验证"
        outputView.string = text
        screenshotButton.isHidden = true
        scrollToTop()
    }

    func showBrowserVerificationResult(_ result: BrowserVerificationResult) {
        guard segmented.selectedSegment == 3 else { return }
        let status: String
        switch result.status {
        case .passed: status = "● 已通过"
        case .skipped: status = "○ 已跳过"
        case .cancelled: status = "○ 已取消"
        default: status = "× 未通过"
        }
        let screenshot = result.screenshots.first?.path ?? "无截图"
        screenshotButton.isHidden = screenshot == "无截图"
        let layout = result.layoutFindings.isEmpty ? "0 个问题" : "\(result.layoutFindings.count) 个问题"
        outputView.string = """
        浏览器验证

        \(status)

        页面
        \(result.devServerURL ?? "未启动")

        运行环境
        \(result.browserRuntime)

        视口
        \(result.viewport.width) × \(result.viewport.height)

        Console
        \(result.consoleMessages.count) errors · \(result.consoleWarnings.count) warnings

        Network
        \(result.failedRequests.count) failed

        Layout
        \(layout)

        截图
        \(screenshot)

        \(result.summary)
        """
        scrollToTop()
    }

    private func loadEcosystem(force: Bool = false) {
        guard !projectPath.isEmpty else {
            outputView.string = "尚未选择项目。"
            return
        }
        summaryLabel.stringValue = "项目智能 · 正在扫描…"
        outputView.string = "项目智能\n\n● 正在建立本地项目索引…\n\n首次扫描在后台进行，Agent 仍可继续工作。"
        let requestID = UUID()
        intelligenceRequestID = requestID
        intelligence.index(projectPath: projectPath, force: force) { [weak self] overview in
            guard let self, self.intelligenceRequestID == requestID else { return }
            self.latestIntelligence = overview
            self.renderProjectIntelligence(overview)
            self.loadEcosystemServices(requestID: requestID)
        }
    }

    private func renderProjectIntelligence(_ overview: ProjectIntelligenceOverview) {
        guard segmented.selectedSegment == 2 else { return }
        let body: String
        if let index = overview.index {
            let status = overview.status == .ready ? "● 已就绪" : "○ \(overview.status.rawValue)"
            let stacks = index.project.frameworks.isEmpty ? "未识别" : index.project.frameworks.joined(separator: "、")
            let last = Self.relativeDate(index.project.lastIndexedAt)
            let warnings = index.warnings.isEmpty ? "" : "\n\n提示：\n" + index.warnings.map { "• \($0)" }.joined(separator: "\n")
            body = """
            项目智能

            \(status)

            文件        \(index.fileCount)
            模块        \(index.moduleCount)
            符号        \(index.symbolCount)
            测试        \(index.testCount)

            项目栈      \(stacks)
            上次更新    \(last)
            增量复用    \(index.reusedFileCount) 个文件
            本次解析    \(index.changedFileCount) 个文件
            \(warnings)

            下方仍可查看 MCP、插件与技能状态。
            """
        } else {
            body = "项目智能\n\n⚠ 项目索引暂不可用\n\n\(overview.error ?? "正在等待首次扫描")\n\nAgent 将回退到传统文件搜索、grep 和 read 工具。"
        }
        outputView.string = Self.capped(body)
        summaryLabel.stringValue = overview.index.map { "项目智能 · \($0.fileCount) 个文件" } ?? "项目索引暂不可用"
        scrollToTop()
    }

    private static func relativeDate(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86400) 天前"
    }

    private func loadEcosystemServices(requestID: UUID? = nil) {
        let expectedRequestID = requestID ?? intelligenceRequestID
        summaryLabel.stringValue = "正在读取扩展生态…"
        runInBackground { [projectPath] in
            guard let executable = BackendLocator.bundledBinaryURL ?? BackendLocator.wrapperURL else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.intelligenceRequestID == expectedRequestID else { return }
                    self.outputView.string = Self.capped((self.outputView.string.isEmpty ? "项目智能\n\n" : self.outputView.string + "\n\n") + "生态工具暂不可用：未找到 Nexus 编码代理。")
                    self.summaryLabel.stringValue = self.latestIntelligence?.index.map { "项目智能 · \($0.fileCount) 个文件" } ?? "项目索引暂不可用"
                }
                return
            }
            let environment = BackendLocator.processEnvironment()
            let mcp = Self.run(
                executable: executable.path,
                arguments: ["mcp", "list"],
                environment: environment
            )
            let plugins = Self.run(
                executable: executable.path,
                arguments: ["plugin", "list"],
                environment: environment
            )
            let home = FileManager.default.homeDirectoryForCurrentUser
            let skillFolders = [
                home.appendingPathComponent(".nexus/skills").path,
                URL(fileURLWithPath: projectPath).appendingPathComponent(".nexus/skills").path,
                URL(fileURLWithPath: projectPath).appendingPathComponent(".codex/skills").path,
            ]
            let skills = skillFolders.flatMap { folder -> [String] in
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
                return names.map { "\(folder)/\($0)" }
            }
            let skillText = skills.isEmpty
                ? "尚未发现技能目录。"
                : skills.map { "• \($0)" }.joined(separator: "\n")
            let ecosystem = """
            MCP 服务器
            \(Self.productizedEcosystemText(mcp.output, empty: "尚未配置 MCP 服务器。"))

            插件
            \(Self.productizedEcosystemText(plugins.output, empty: "尚未安装插件。"))

            技能
            \(skillText)

            配置文件
            \(NexusConfiguration.shared.configURL.path)
            """
            DispatchQueue.main.async { [weak self] in
                guard let self, self.intelligenceRequestID == expectedRequestID else { return }
                let projectSection: String
                if let index = self.latestIntelligence?.index {
                    projectSection = "项目智能\n\n● 已就绪\n\n文件        \(index.fileCount)\n模块        \(index.moduleCount)\n符号        \(index.symbolCount)\n测试        \(index.testCount)\n\n上次更新    \(Self.relativeDate(index.project.lastIndexedAt))\n\n[重新索引]\n"
                } else {
                    projectSection = "项目智能\n\n⚠ 项目索引暂不可用\n\n[重新索引]\n"
                }
                self.summaryLabel.stringValue = self.latestIntelligence?.index.map { "项目智能 · \($0.fileCount) 个文件" } ?? "项目索引暂不可用"
                self.outputView.string = Self.capped(projectSection + "\n" + ecosystem)
                self.scrollToTop()
            }
        }
    }

    private static func productizedEcosystemText(_ raw: String, empty: String) -> String {
        let clean = raw
            .replacingOccurrences(of: #"\u001B\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return empty }
        let lowered = clean.lowercased()
        if lowered.contains("no mcp servers configured") { return "尚未配置 MCP 服务器。" }
        if lowered.contains("no plugins installed") { return "尚未安装插件。" }
        if lowered.contains("no skills found") || lowered.contains("no skills installed") { return "尚未发现技能。" }
        if lowered.contains("usage:") || lowered.contains("unknown command") || lowered.contains("command not found") {
            return "生态服务暂不可用，请使用输入框配置。"
        }
        return clean.count > 1_200 ? String(clean.prefix(1_200)) + "…" : clean
    }

    @objc private func segmentChanged() {
        updateMode()
        refresh()
    }

    @objc private func primaryAction() {
        if segmented.selectedSegment == 3 {
            runTerminalCommand()
        } else if segmented.selectedSegment == 2 {
            if commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadEcosystem(force: true)
            } else {
                manageExtension()
            }
        } else {
            refresh()
        }
    }

    @objc private func browserVerificationClicked() {
        onBrowserVerification?()
    }

    @objc private func cancelGitHubWorkflowClicked() {
        guard let taskID = githubSnapshot.taskID else { return }
        let alert = NSAlert()
        alert.messageText = "停止等待 GitHub CI？"
        alert.informativeText = "停止 AI Dev One 对此 GitHub 任务的后续自动处理？\n远程 PR、分支和 GitHub CI 不会被删除或取消。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止等待")
        alert.addButton(withTitle: "继续等待")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onCancelGitHubTask?(taskID)
    }

    @objc private func viewGitHubPullRequestClicked() {
        guard let raw = githubSnapshot.metadata?.pullRequestURL,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func browserScreenshotClicked() {
        let path = outputView.string
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("/") })
            .map(String.init)
        guard let path, let image = NSImage(contentsOfFile: path) else { return }
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "浏览器验证截图"
        window.isReleasedWhenClosed = false
        window.contentView = imageView
        window.center()
        window.makeKeyAndOrderFront(nil)
        screenshotWindow = window
    }

    private func manageExtension() {
        let source = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            refresh()
            return
        }
        guard let executable = BackendLocator.bundledBinaryURL ?? BackendLocator.wrapperURL else {
            outputView.string = "未找到 Nexus 编码代理。"
            return
        }
        commandField.stringValue = ""
        actionButton.isEnabled = false
        let isMCPCommand = source.hasPrefix("mcp ")
        let arguments: [String]
        let actionName: String
        if isMCPCommand {
            arguments = source.split(whereSeparator: \.isWhitespace).map(String.init)
            actionName = "配置 MCP"
        } else {
            arguments = ["plugin", "install", "--trust", source]
            actionName = "安装插件"
        }
        outputView.string = "正在\(actionName)：\(source)\n\n"
        runInBackground {
            let result = Self.run(
                executable: executable.path,
                arguments: arguments,
                environment: BackendLocator.processEnvironment()
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.actionButton.isEnabled = true
                if result.code == 0 {
                    self.outputView.string = "\(actionName)完成。\n\n\(result.output)"
                    self.loadEcosystem()
                } else {
                    self.outputView.string = "\(actionName)失败。\n\n\(result.output)"
                }
            }
        }
    }

    @objc private func runTerminalCommand() {
        guard runningProcess == nil else { return }
        let command = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        commandField.stringValue = ""
        outputView.string += "$ \(command)\n"
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", command]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        task.environment = ProcessInfo.processInfo.environment
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.outputView.string += text
                self?.scrollToBottom()
            }
        }
        task.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.runningProcess = nil
                self.actionButton.isEnabled = true
                self.outputView.string += text
                self.outputView.string += "\n[命令结束，退出代码 \(process.terminationStatus)]\n\n"
                self.scrollToBottom()
            }
        }
        do {
            try task.run()
            runningProcess = task
            actionButton.isEnabled = false
        } catch {
            outputView.string += "无法运行命令：\(error.localizedDescription)\n"
        }
    }

    @objc private func closePanel() {
        onClose?()
    }

    private func runInBackground(_ body: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: body)
    }

    private func scrollToTop() {
        outputView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func scrollToBottom() {
        outputView.scrollRangeToVisible(
            NSRange(location: outputView.string.utf16.count, length: 0)
        )
    }

    private static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> (code: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let environment {
            task.environment = environment
        }
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private static func capped(_ text: String) -> String {
        let limit = 600_000
        if text.utf8.count <= limit {
            return text
        }
        return String(text.prefix(limit)) + "\n\n…内容过长，已截断显示。"
    }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController {
    private let keyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let endpointField = NSTextField()
    private let keyStatus = label("", size: 11)
    private let resultLabel = label("", size: 12)
    private let saveButton = NSButton(title: "保存设置", target: nil, action: nil)
    private let resetLayoutButton = NSButton(title: "重置界面布局", target: nil, action: nil)
    var onSaved: (() -> Void)?
    var onResetLayout: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nexus 设置"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        reload()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.canvas.cgColor

        let title = label("设置", size: 24, weight: .semibold)
        let subtitle = label("管理模型和本地凭据", size: 13, color: Palette.secondaryText)
        let card = LayerView(fillColor: Palette.elevated, cornerRadius: 12, strokeColor: Palette.border)
        let providerValue = label("DeepSeek", size: 13, weight: .medium)

        [title, subtitle, card, providerValue, keyField, modelField, endpointField, keyStatus, resultLabel, saveButton, resetLayoutButton]
            .forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        let providerLabel = label("模型提供商", size: 12, weight: .medium, color: Palette.secondaryText)
        let apiLabel = label("DeepSeek API 密钥", size: 12, weight: .medium, color: Palette.secondaryText)
        let modelLabel = label("模型", size: 12, weight: .medium, color: Palette.secondaryText)
        let endpointLabel = label("接口地址", size: 12, weight: .medium, color: Palette.secondaryText)
        let privacy = label(
            "密钥仅保存在本机 macOS 钥匙串中，不会写入配置文件或日志。",
            size: 11,
            color: Palette.secondaryText
        )
        [providerLabel, apiLabel, modelLabel, endpointLabel, privacy]
            .forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        keyField.placeholderString = "输入新密钥以保存或替换"
        modelField.placeholderString = "例如 gpt-4.1"
        endpointField.placeholderString = "https://api.deepseek.com"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        resetLayoutButton.bezelStyle = .rounded
        resetLayoutButton.target = self
        resetLayoutButton.action = #selector(resetLayout)
        resultLabel.maximumNumberOfLines = 2

        content.addSubview(title)
        content.addSubview(subtitle)
        content.addSubview(card)
        card.addSubview(providerLabel)
        card.addSubview(providerValue)
        card.addSubview(apiLabel)
        card.addSubview(keyField)
        card.addSubview(keyStatus)
        card.addSubview(modelLabel)
        card.addSubview(modelField)
        card.addSubview(endpointLabel)
        card.addSubview(endpointField)
        card.addSubview(privacy)
        content.addSubview(resultLabel)
        content.addSubview(saveButton)
        content.addSubview(resetLayoutButton)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            card.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            card.heightAnchor.constraint(equalToConstant: 300),

            providerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            providerLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            providerValue.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 160),
            providerValue.centerYAnchor.constraint(equalTo: providerLabel.centerYAnchor),

            apiLabel.leadingAnchor.constraint(equalTo: providerLabel.leadingAnchor),
            apiLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 29),
            keyField.leadingAnchor.constraint(equalTo: providerValue.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            keyField.centerYAnchor.constraint(equalTo: apiLabel.centerYAnchor),
            keyField.heightAnchor.constraint(equalToConstant: 27),
            keyStatus.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            keyStatus.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 5),

            modelLabel.leadingAnchor.constraint(equalTo: providerLabel.leadingAnchor),
            modelLabel.topAnchor.constraint(equalTo: apiLabel.bottomAnchor, constant: 58),
            modelField.leadingAnchor.constraint(equalTo: providerValue.leadingAnchor),
            modelField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            modelField.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
            modelField.heightAnchor.constraint(equalToConstant: 27),

            endpointLabel.leadingAnchor.constraint(equalTo: providerLabel.leadingAnchor),
            endpointLabel.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 35),
            endpointField.leadingAnchor.constraint(equalTo: providerValue.leadingAnchor),
            endpointField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            endpointField.centerYAnchor.constraint(equalTo: endpointLabel.centerYAnchor),
            endpointField.heightAnchor.constraint(equalToConstant: 27),

            privacy.leadingAnchor.constraint(equalTo: providerLabel.leadingAnchor),
            privacy.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            privacy.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),

            resultLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            resultLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            resultLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetLayoutButton.leadingAnchor, constant: -12),
            saveButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            saveButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 22),
            saveButton.widthAnchor.constraint(equalToConstant: 100),
            resetLayoutButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            resetLayoutButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            resetLayoutButton.widthAnchor.constraint(equalToConstant: 126),
        ])
    }

    private func reload() {
        let configuration = NexusConfiguration.shared
        modelField.stringValue = configuration.value(
            named: "model",
            inSection: "model.openai-coding"
        ) ?? "gpt-4.1"
        endpointField.stringValue = configuration.value(
            named: "base_url",
            inSection: "model.openai-coding"
        ) ?? "https://api.deepseek.com"
        updateKeyStatus()
    }

    private func updateKeyStatus() {
        let saved = NexusConfiguration.shared.hasAPIKey
        keyStatus.stringValue = saved ? "已安全保存；留空不会修改" : "尚未保存密钥"
        keyStatus.textColor = saved ? Palette.success : Palette.warning
    }

    @objc private func save() {
        resultLabel.stringValue = ""
        do {
            try NexusConfiguration.shared.updateOpenAI(
                model: modelField.stringValue,
                baseURL: endpointField.stringValue
            )
        } catch {
            showResult(error.localizedDescription, success: false)
            return
        }

        let newKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else {
            showResult("设置已保存。", success: true)
            onSaved?()
            return
        }
        if newKey.contains("\"") || newKey.contains("\\") || newKey.contains("\n") {
            showResult("接口密钥格式不正确。", success: false)
            return
        }
        saveButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try SecureCredentialStore.save(newKey)
                DispatchQueue.main.async {
                    guard let self else { return }
                    // 清除早期版本可能留下的 TOML 明文；失败时让用户知道，
                    // 但不把敏感内容拼进错误信息。
                    do {
                        try NexusConfiguration.shared.removePlaintextAPIKey()
                    } catch {
                        self.saveButton.isEnabled = true
                        self.showResult("凭据已保存，但旧配置清理失败，请重试。", success: false)
                        return
                    }
                    self.saveButton.isEnabled = true
                    self.keyField.stringValue = ""
                    self.updateKeyStatus()
                    self.showResult("设置和安全凭据已保存。", success: true)
                    self.onSaved?()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.saveButton.isEnabled = true
                    self.showResult("无法保存安全凭据：\(error.localizedDescription)", success: false)
                }
            }
        }
    }

    @objc private func resetLayout() {
        onResetLayout?()
        showResult("界面布局已恢复默认。", success: true)
    }

    private func showResult(_ text: String, success: Bool) {
        resultLabel.stringValue = text
        resultLabel.textColor = success ? Palette.success : NSColor.systemRed
    }
}

// MARK: - 可调三栏布局

/// 三栏工作区的原生 AppKit 分栏容器。
///
/// 这里使用 NSSplitView 承载三栏和分隔线绘制，但由本类接管分隔线拖拽：
/// 面板使用手动 frame 布局时，原生 tracking loop 不会稳定交付 resize 回调，
/// 所以事件在本类内以固定 drag origin 计算并在 mouseUp 时持久化。
/// 两侧尺寸写入 UserDefaults，效果等价于 Web Renderer 中的 localStorage。
final class ResizableSplitView: NSSplitView, NSSplitViewDelegate {
    static let sidebarStorageKey = "ai-dev-one.sidebar-width"
    static let workspaceStorageKey = "ai-dev-one.workspace-width"

    let sidebarDefaultWidth: CGFloat = 260
    let sidebarMinimumWidth: CGFloat = 220
    let sidebarMaximumWidth: CGFloat = 420
    let workspaceDefaultWidth: CGFloat = 340
    let workspaceMinimumWidth: CGFloat = 280
    let workspaceMaximumWidth: CGFloat = 620
    let chatMinimumWidth: CGFloat = 520

    private(set) var sidebarWidth: CGFloat
    private(set) var workspaceWidth: CGFloat
    private var applyingStoredWidths = false
    private var didRestoreInitialWidths = false
    private var hoveredDivider: Int?
    private var draggingDivider: Int?
    private var dragStartX: CGFloat?
    private var dragStartSidebarWidth: CGFloat?
    private var dragStartWorkspaceWidth: CGFloat?
    private var dividerTrackingAreas: [NSTrackingArea] = []

    private var resizeDiagnosticsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "ai-dev-one.resizable-diagnostics")
    }

    private func resizeDiagnostic(_ message: String) {
        guard resizeDiagnosticsEnabled else { return }
        NSLog("[Resizable] %@", message)
    }

    override init(frame frameRect: NSRect) {
        let defaults = UserDefaults.standard
        let savedSidebar = defaults.object(forKey: Self.sidebarStorageKey) as? NSNumber
        let savedWorkspace = defaults.object(forKey: Self.workspaceStorageKey) as? NSNumber
        sidebarWidth = savedSidebar.map { CGFloat(truncating: $0) } ?? sidebarDefaultWidth
        workspaceWidth = savedWorkspace.map { CGFloat(truncating: $0) } ?? workspaceDefaultWidth
        super.init(frame: frameRect)
        // 启动时先把历史值规范化，异常值回到默认值，避免旧版本数据撑破三栏。
        let normalizedSidebar = normalizedStoredWidth(
            sidebarWidth,
            defaultValue: sidebarDefaultWidth,
            minimum: sidebarMinimumWidth,
            maximum: sidebarMaximumWidth
        )
        let normalizedWorkspace = normalizedStoredWidth(
            workspaceWidth,
            defaultValue: workspaceDefaultWidth,
            minimum: workspaceMinimumWidth,
            maximum: workspaceMaximumWidth
        )
        if normalizedSidebar != sidebarWidth {
            defaults.removeObject(forKey: Self.sidebarStorageKey)
        }
        if normalizedWorkspace != workspaceWidth {
            defaults.removeObject(forKey: Self.workspaceStorageKey)
        }
        sidebarWidth = normalizedSidebar
        workspaceWidth = normalizedWorkspace
        defaults.set(Double(sidebarWidth), forKey: Self.sidebarStorageKey)
        defaults.set(Double(workspaceWidth), forKey: Self.workspaceStorageKey)
        isVertical = true
        dividerStyle = .thin
        arrangesAllSubviews = false
        delegate = self
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        autoresizesSubviews = true
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func layout() {
        super.layout()
        applyStoredWidthsIfPossible()
        updateTrackingAreasForDividers()
    }

    override func adjustSubviews() {
        // NSSplitView 默认会按 fittingSize 比例重排非 arranged subviews，
        // 这会把用户的 260/340 初始值压回内容的最小宽度。这里接管重排，
        // 让保存的 pane 宽度成为唯一来源，同时仍由 delegate 负责拖拽约束。
        if bounds.width > 0, subviews.count >= 3, !applyingStoredWidths, draggingDivider == nil {
            applyStoredWidthsIfPossible()
        } else {
            super.adjustSubviews()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingAreasForDividers()
    }

    /// Divider hit testing must win over the pane views themselves.  The
    /// visible divider is one pixel wide, but the interactive target is ten
    /// pixels wide so a normal mouse can reliably start a drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if dividerIndex(at: point.x) != nil {
            return self
        }
        return super.hitTest(point)
    }

    override func drawDivider(in rect: NSRect) {
        let index = dividerIndex(at: rect.midX)
        let alpha: CGFloat
        if draggingDivider == index {
            alpha = 0.70
        } else if hoveredDivider == index {
            alpha = 0.40
        } else {
            alpha = 0.10
        }

        let lineRect = isVertical
            ? NSRect(x: rect.midX - 0.5, y: rect.minY, width: 1, height: rect.height)
            : NSRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1)
        if alpha > 0.2 {
            let shadow = NSShadow()
            shadow.shadowColor = Palette.accent.withAlphaComponent(alpha * 0.45)
            shadow.shadowBlurRadius = draggingDivider == index ? 12 : 7
            shadow.shadowOffset = .zero
            shadow.set()
        }
        Palette.accent.withAlphaComponent(alpha).setFill()
        NSBezierPath(rect: lineRect).fill()
        NSShadow().set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for index in 0..<max(0, subviews.count - 1) {
            let rect = dividerFrame(at: index).insetBy(dx: -5, dy: 0)
            addCursorRect(rect, cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = dividerIndex(at: point.x)
        guard let index else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount >= 2 {
            resetDivider(index)
            return
        }

        // Do not delegate to NSSplitView's internal tracking loop.  The
        // panes are laid out manually (arrangesAllSubviews=false), so the
        // native divider loop receives the down event but does not emit a
        // usable resize callback.  Keep one immutable drag origin and route
        // subsequent mouseDragged/mouseUp events through this view instead.
        draggingDivider = index
        dragStartX = point.x
        dragStartSidebarWidth = sidebarWidth
        dragStartWorkspaceWidth = workspaceWidth
        resizeDiagnostic(
            "divider=\(index) mouseDown startX=\(point.x) "
                + "startSidebar=\(sidebarWidth) startWorkspace=\(workspaceWidth)"
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = draggingDivider,
              let startX = dragStartX,
              let startSidebar = dragStartSidebarWidth,
              let startWorkspace = dragStartWorkspaceWidth else {
            super.mouseDragged(with: event)
            return
        }

        let currentX = convert(event.locationInWindow, from: nil).x
        let translation = currentX - startX
        if index == 0 {
            let maximum = min(
                sidebarMaximumWidth,
                bounds.width - startWorkspace - chatMinimumWidth - dividerThickness * 2
            )
            let candidate = startSidebar + translation
            sidebarWidth = clamp(candidate, sidebarMinimumWidth, max(sidebarMinimumWidth, maximum))
        } else {
            let maximum = min(
                workspaceMaximumWidth,
                bounds.width - startSidebar - chatMinimumWidth - dividerThickness * 2
            )
            let candidate = startWorkspace - translation
            workspaceWidth = clamp(candidate, workspaceMinimumWidth, max(workspaceMinimumWidth, maximum))
        }

        setPaneFrames(sidebarWidth: sidebarWidth, workspaceWidth: workspaceWidth)
        resizeDiagnostic(
            "divider=\(index) dragChanged currentX=\(currentX) translation=\(translation) "
                + "newSidebar=\(sidebarWidth) newWorkspace=\(workspaceWidth)"
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let index = draggingDivider else {
            super.mouseUp(with: event)
            return
        }

        // Apply one final sample so a short drag that only produces a mouseUp
        // still lands at the pointer's final position.
        mouseDragged(with: event)
        persistCurrentWidths()
        resizeDiagnostic(
            "divider=\(index) dragEnded sidebar=\(sidebarWidth) workspace=\(workspaceWidth)"
        )
        draggingDivider = nil
        dragStartX = nil
        dragStartSidebarWidth = nil
        dragStartWorkspaceWidth = nil
        needsDisplay = true
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        // 视觉线保持 1px，但命中区域为 10px，方便精确拖拽。
        proposedEffectiveRect.insetBy(dx: -5, dy: 0)
    }

    func splitView(
        _ splitView: NSSplitView,
        additionalEffectiveRectOfDividerAt dividerIndex: Int
    ) -> NSRect {
        let rect = dividerFrame(at: dividerIndex)
        return rect.insetBy(dx: -5, dy: 0)
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let totalWidth = bounds.width
        let divider = dividerThickness
        let twoDividers = divider * 2

        if dividerIndex == 0 {
            // 先保证 Chat 和 Workspace 的最小宽度，再允许 Sidebar 在其范围内变化。
            let maximum = min(
                sidebarMaximumWidth,
                totalWidth - workspaceMinimumWidth - chatMinimumWidth - twoDividers
            )
            return clamp(proposedPosition, sidebarMinimumWidth, max(sidebarMinimumWidth, maximum))
        }

        let leftWidth = subviews.indices.contains(0) ? subviews[0].frame.width : sidebarWidth
        let minimumPosition = max(
            leftWidth + divider + chatMinimumWidth,
            totalWidth - workspaceMaximumWidth
        )
        let maximumPosition = totalWidth - workspaceMinimumWidth
        return clamp(proposedPosition, minimumPosition, max(minimumPosition, maximumPosition))
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applyingStoredWidths, subviews.count >= 3 else { return }
        persistCurrentWidths()
        needsDisplay = true
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // 窗口变化时重排三栏，但不改变用户保存的两侧宽度；仅在空间不足时按约束压缩。
        applyStoredWidthsIfPossible()
    }

    func resetDivider(_ dividerIndex: Int) {
        if dividerIndex == 0 {
            sidebarWidth = sidebarDefaultWidth
        } else if dividerIndex == 1 {
            workspaceWidth = workspaceDefaultWidth
        } else {
            return
        }
        applyStoredWidthsIfPossible()
        persistCurrentWidths()
        needsDisplay = true
    }

    func resetLayout() {
        UserDefaults.standard.removeObject(forKey: Self.sidebarStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.workspaceStorageKey)
        sidebarWidth = sidebarDefaultWidth
        workspaceWidth = workspaceDefaultWidth
        applyStoredWidthsIfPossible()
        persistCurrentWidths()
        needsDisplay = true
    }

    func restoreStoredWidths() {
        didRestoreInitialWidths = true
        applyStoredWidthsIfPossible()
        needsDisplay = true
    }

    private func applyStoredWidthsIfPossible() {
        guard bounds.width > 0, subviews.count >= 3, !applyingStoredWidths, draggingDivider == nil else { return }
        applyingStoredWidths = true

        let totalWidth = bounds.width
        let divider = dividerThickness
        let twoDividers = divider * 2
        let maxSidebar = min(
            sidebarMaximumWidth,
            totalWidth - workspaceMinimumWidth - chatMinimumWidth - twoDividers
        )
        let safeSidebar = clamp(
            sidebarWidth,
            sidebarMinimumWidth,
            max(sidebarMinimumWidth, maxSidebar)
        )
        sidebarWidth = safeSidebar
        let minimumWorkspace = workspaceMinimumWidth
        let maximumWorkspace = min(
            workspaceMaximumWidth,
            max(minimumWorkspace, totalWidth - safeSidebar - chatMinimumWidth - twoDividers)
        )
        workspaceWidth = clamp(workspaceWidth, minimumWorkspace, maximumWorkspace)
        setPaneFrames(sidebarWidth: safeSidebar, workspaceWidth: workspaceWidth)

        applyingStoredWidths = false
        persistCurrentWidths()
    }

    private func setPaneFrames(sidebarWidth: CGFloat, workspaceWidth: CGFloat) {
        guard subviews.count >= 3 else { return }
        let divider = dividerThickness
        let totalWidth = bounds.width
        let height = bounds.height
        let chatWidth = max(0, totalWidth - sidebarWidth - workspaceWidth - divider * 2)
        subviews[0].frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: height)
        subviews[1].frame = NSRect(
            x: sidebarWidth + divider,
            y: 0,
            width: chatWidth,
            height: height
        )
        subviews[2].frame = NSRect(
            x: sidebarWidth + divider + chatWidth + divider,
            y: 0,
            width: workspaceWidth,
            height: height
        )
    }

    private func persistCurrentWidths() {
        // AppKit 在窗口初次安装 contentView 时会先用 fittingSize 重排一次。
        // 在真正恢复保存值之前禁止这次中间帧覆盖 UserDefaults。
        guard didRestoreInitialWidths, bounds.width > 0, subviews.count >= 3,
              subviews[0].frame.width > 0, subviews[2].frame.width > 0 else { return }
        let sidebar = clamp(subviews[0].frame.width, sidebarMinimumWidth, sidebarMaximumWidth)
        let workspace = clamp(subviews[2].frame.width, workspaceMinimumWidth, workspaceMaximumWidth)
        sidebarWidth = sidebar
        workspaceWidth = workspace
        UserDefaults.standard.set(Double(sidebar), forKey: Self.sidebarStorageKey)
        UserDefaults.standard.set(Double(workspace), forKey: Self.workspaceStorageKey)
    }

    private func updateTrackingAreasForDividers() {
        dividerTrackingAreas.forEach(removeTrackingArea)
        dividerTrackingAreas.removeAll(keepingCapacity: true)
        for index in 0..<max(0, subviews.count - 1) {
            let rect = dividerFrame(at: index).insetBy(dx: -5, dy: 0)
            guard !rect.isEmpty else { continue }
            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: ["divider": index]
            )
            addTrackingArea(area)
            dividerTrackingAreas.append(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hoveredDivider = (event.trackingArea?.userInfo?["divider"] as? Int)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredDivider = nil
        needsDisplay = true
    }

    private func dividerIndex(at x: CGFloat) -> Int? {
        for index in 0..<max(0, subviews.count - 1) {
            let rect = dividerFrame(at: index).insetBy(dx: -5, dy: 0)
            if rect.minX...rect.maxX ~= x { return index }
        }
        return nil
    }

    private func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }

    private func normalizedStoredWidth(
        _ value: CGFloat,
        defaultValue: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard value.isFinite, value >= minimum, value <= maximum else {
            return defaultValue
        }
        return value
    }

    private func dividerFrame(at index: Int) -> NSRect {
        guard index >= 0, index + 1 < subviews.count else { return .zero }
        if isVertical {
            let left = subviews[index].frame.maxX
            let right = subviews[index + 1].frame.minX
            let center = abs(right - left) < 2 ? (left + right) / 2 : left
            return NSRect(
                x: center - dividerThickness / 2,
                y: bounds.minY,
                width: max(dividerThickness, right - left),
                height: bounds.height
            )
        }
        let top = subviews[index].frame.maxY
        let bottom = subviews[index + 1].frame.minY
        let center = abs(top - bottom) < 2 ? (top + bottom) / 2 : top
        return NSRect(
            x: bounds.minX,
            y: center - dividerThickness / 2,
            width: bounds.width,
            height: max(dividerThickness, top - bottom)
        )
    }
}

// MARK: - 主窗口

final class MainViewController: NSViewController {
    var onRequestWindowSize: ((NSSize) -> Void)?
    var onOpenMainWindow: (() -> Void)?

    private let store = SessionStore.shared
    private let topBar = TopBarView()
    private let bottomBar = BottomStatusBarView()
    private let sidebar = SidebarView()
    private let chat = ChatContentView()
    private let workspacePanel = WorkspacePanelView()
    private let split = ResizableSplitView()
    private let runner = NexusRunner()
    private let transactionStore = TaskTransactionStore.shared
    private lazy var githubWorkflowCoordinator = GitHubWorkflowCoordinator(
        provider: GitHubCLIProvider(),
        store: transactionStore
    )
    private let recovery = CoreRecoveryCoordinator()
    private let browserVerification = BrowserVerificationService.shared
    private var workMonitorController: WorkMonitorWindowController?
    private var workSummary = WorkActivitySummary.idle
    private var selectedID: UUID?
    private var streamingText = ""
    private var settingsController: SettingsWindowController?
    private var didPrepareForDisplay = false
    private var activeTransaction: TaskTransaction?
    private var activePrompt: String?
    private var activeApproval: TaskApproval?
    private var activeSessionID: UUID?
    private var activeMessageID: UUID?
    /// Preserve the first tool failure so a later backend `end` event cannot
    /// incorrectly turn the task into a completed run.
    private var activeToolFailure: String?
    private var pipeline = AgentPipelineStateMachine()
    private var verificationInFlight = false
    private var browserVerificationInFlight = false
    private var browserRepairAttempts = 0
    /// A task's browser gate is complete only after both desktop and mobile
    /// viewports have reported.  This flag is reset for every repair loop.
    private var browserMobileVerificationCompleted = false
    private var checkpointInFlight = false
    /// Parent task finalization is independent from BrowserVerification's
    /// short-lived WKWebView/server resources.  This coordinator also makes
    /// late runtime `end` events and duplicate callbacks idempotent.
    private var finalization = TaskFinalizationCoordinator(taskID: "idle")

    override func loadView() {
        let root = LayerView(fillColor: Palette.canvas)
        root.frame = NSRect(
            x: 0,
            y: 0,
            width: AppDelegate.defaultWindowWidth,
            height: AppDelegate.defaultWindowHeight
        )
        root.autoresizingMask = [.width, .height]
        view = root

        let top = topBar
        top.translatesAutoresizingMaskIntoConstraints = false
        let bottom = bottomBar
        bottom.translatesAutoresizingMaskIntoConstraints = false
        split.addSubview(sidebar)
        split.addSubview(chat)
        split.addSubview(workspacePanel)
        sidebar.translatesAutoresizingMaskIntoConstraints = true
        chat.translatesAutoresizingMaskIntoConstraints = true
        workspacePanel.translatesAutoresizingMaskIntoConstraints = true
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 2)
        chat.setContentCompressionResistancePriority(.required, for: .horizontal)
        chat.widthAnchor.constraint(greaterThanOrEqualToConstant: split.chatMinimumWidth).isActive = true
        let backdrop = ForestBackdropView()
        root.addSubview(backdrop)
        backdrop.pinEdges(to: root)
        root.addSubview(top)
        root.addSubview(bottom)
        root.addSubview(split)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            top.topAnchor.constraint(equalTo: root.topAnchor),
            top.heightAnchor.constraint(equalToConstant: 66),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 34),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            split.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 10),
            split.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -10),
        ])
        workspacePanel.isHidden = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebar.onNewTask = { [weak self] in self?.newTask() }
        sidebar.onSelect = { [weak self] id in self?.select(id: id) }
        sidebar.onSettings = { [weak self] in self?.openSettings() }
        sidebar.onEcosystem = { [weak self] in self?.showWorkspace(segment: 2) }
        sidebar.onDelete = { [weak self] id in self?.delete(id: id) }
        chat.onProject = { [weak self] in self?.chooseProject() }
        chat.onShowWorkspace = { [weak self] segment in
            self?.showWorkspace(segment: segment)
        }
        chat.onOpenSettings = { [weak self] in self?.openSettings() }
        chat.onRetry = { [weak self] in self?.retryLastPrompt() }
        chat.composer.onSend = { [weak self] in self?.send() }
        chat.composer.onStop = { [weak self] in self?.stop() }
        bottomBar.onRestartCore = { [weak self] in self?.restartCoreManually() }
        bottomBar.onViewCoreLog = { [weak self] in self?.openCoreLog() }
        workspacePanel.onClose = { [weak self] in
            self?.workspacePanel.isHidden = true
        }
        workspacePanel.onBrowserVerification = { [weak self] in
            self?.startBrowserVerificationFromWorkspace()
        }
        workspacePanel.onCancelGitHubTask = { [weak self] taskID in
            self?.githubWorkflowCoordinator.cancel(taskID: taskID)
        }
        topBar.onSettings = { [weak self] in self?.openSettings() }
        topBar.onWorkMonitor = { [weak self] in self?.showWorkMonitor() }

        workspacePanel.updateGitHubWorkflow(GitHubWorkflowSnapshot(
            transaction: nil,
            restoring: true,
            error: nil,
            activePollerCount: 0
        ))
        githubWorkflowCoordinator.onUpdate = { [weak self] snapshot in
            self?.workspacePanel.updateGitHubWorkflow(snapshot)
            self?.updateWorkGitHub(snapshot)
        }
        githubWorkflowCoordinator.restore()

        refreshSidebar()
        if let first = store.sessions.first {
            select(id: first.id)
        } else {
            newTask()
        }
        workspacePanel.refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        prepareForDisplay()
    }

    func prepareForDisplay() {
        guard !didPrepareForDisplay else { return }
        didPrepareForDisplay = true
        // 首次进入窗口后再应用一次，避开 AppKit 在 contentView 安装期间
        // 对 NSSplitView 做的默认 fittingSize 重排。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.view.needsLayout = true
            self?.view.layoutSubtreeIfNeeded()
            self?.split.layoutSubtreeIfNeeded()
            self?.split.restoreStoredWidths()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.chat.composer.focus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.writeLayoutProbeIfRequested()
        }
    }

    private func writeLayoutProbeIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let reportPath = environment["NEXUS_LAYOUT_PROBE"], !reportPath.isEmpty else { return }
        let paneFrames = split.subviews.enumerated().map { index, pane in
            "pane[\(index)]=\(NSStringFromRect(pane.frame))"
        }.joined(separator: "\n")
        var hierarchyLines: [String] = []
        var ancestor = view.superview
        for index in 0..<4 {
            guard let current = ancestor else {
                hierarchyLines.append("ancestor[\(index)]=nil")
                break
            }
            hierarchyLines.append(
                "ancestor[\(index)]=\(NSStringFromClass(type(of: current))) "
                    + "frame=\(NSStringFromRect(current.frame)) "
                    + "bounds=\(NSStringFromRect(current.bounds)) "
                    + "translates=\(current.translatesAutoresizingMaskIntoConstraints)"
            )
            ancestor = current.superview
        }
        let hierarchy = hierarchyLines.joined(separator: "\n")
        let report = """
        window=\(view.window.map { NSStringFromRect($0.frame) } ?? "nil")
        root.frame=\(NSStringFromRect(view.frame))
        root.bounds=\(NSStringFromRect(view.bounds))
        \(hierarchy)
        split.frame=\(NSStringFromRect(split.frame))
        split.bounds=\(NSStringFromRect(split.bounds))
        \(paneFrames)
        sidebar.stored=\(split.sidebarWidth)
        workspace.stored=\(split.workspaceWidth)
        credential.state=\(SecureCredentialStore.loadState.rawValue)
        model.hasAPIKey=\(NexusConfiguration.shared.hasAPIKey)
        """
        try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)

        guard let snapshotPath = environment["NEXUS_LAYOUT_SNAPSHOT"],
              !snapshotPath.isEmpty,
              !view.bounds.isEmpty,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        if let data = representation.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }
    }

    func stopRunningTask() {
        stop()
    }

    /// App lifecycle entry point. Unlike stopping a user task, this marks the
    /// supervisor as intentionally shut down so Process termination cannot
    /// schedule an automatic restart during Cmd+Q/window close.
    func shutdownCore() {
        // App shutdown stops only the local CI observer. A persisted
        // waiting_ci transaction remains recoverable and is not user cancel.
        githubWorkflowCoordinator.stopForAppShutdown()
        if let transaction = activeTransaction,
           transaction.github?.workflowState != .waitingCI,
           finalization.requestCancel(source: .appShutdown) {
            updateTransaction { current in
                _ = current.transition(to: .cancelled, cancellationSource: .appShutdown)
                current.agentStages.append("Task cancelled: app_shutdown")
                current.pipeline = pipeline.snapshot
            }
            if let session = store.sessions.first(where: { $0.id.uuidString.lowercased() == transaction.sessionId }),
               let messageID = activeMessageID {
                finishFailure("任务已停止（应用退出）。", session: session, messageID: messageID)
            }
            browserVerification.cancel()
            activeTransaction = nil
            clearActiveTask()
            verificationInFlight = false
        }
        runner.shutdown()
    }

    private func restartCoreManually() {
        guard let session = selectedSession else {
            bottomBar.setCoreStatus("Core 失败", color: Palette.error)
            return
        }
        let messageID = activeMessageID ?? session.messages.last?.id ?? UUID()
        runner.manualRestart { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleCoreState(state, session: session, messageID: messageID)
            }
        }
    }

    private func openCoreLog() {
        let url = CoreSupervisor.logFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "AI Dev One Core 尚无日志。\n".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func showWorkMonitor() {
        if workMonitorController == nil {
            workMonitorController = WorkMonitorWindowController()
        }
        workMonitorController?.onOpenMainWindow = { [weak self] in
            self?.onOpenMainWindow?()
        }
        workMonitorController?.show(summary: workSummary)
    }

    /// Window 菜单和顶部按钮共用同一个单例入口，避免重复创建监控面板。
    @objc func showWorkMonitorFromMenu() {
        showWorkMonitor()
    }

    /// AppKit 在某些 macOS 版本上不会把 utility NSPanel 计入
    /// applicationShouldTerminateAfterLastWindowClosed 的窗口数量，因此
    /// AppDelegate 需要显式询问监控器是否仍可见。
    var isWorkMonitorVisible: Bool {
        workMonitorController?.window?.isVisible == true
    }

    private func publishWorkMonitor() {
        workMonitorController?.update(summary: workSummary)
    }

    /// Reset only the presentation projection when the user changes Session.
    /// The source of truth remains SessionStore/TaskTransaction/Core state.
    private func resetWorkMonitor(for session: ChatSession) {
        let projectURL = URL(fileURLWithPath: session.projectPath)
        let projectName = projectURL.lastPathComponent.isEmpty ? "未选择项目" : projectURL.lastPathComponent
        workSummary = .idle
        workSummary.taskTitle = session.title == "新任务" ? "等待新的开发任务" : WorkMonitorRedaction.text(session.title, limit: 180)
        workSummary.projectName = projectName
        workSummary.projectPath = session.projectPath
        workSummary.status = latestSystemError(in: session) == nil ? "空闲" : "需要处理"
        workSummary.activity = latestSystemError(in: session) ?? "等待用户提交任务"
        workSummary.purpose = latestSystemError(in: session) == nil
            ? "提交任务后，这里会显示 AI 正在处理的对象和目的。"
            : "查看主窗口中的错误卡片，完成配置或重新连接后再试。"
        workSummary.coreStatus = BackendLocator.wrapperURL == nil ? "Disconnected" : "Ready"
        workSummary.modelStatus = modelState(for: session).monitorLabel
        workSummary.agentStatus = "Agent 空闲"
        publishWorkMonitor()
    }

    private func updateWorkMonitorRuntime(core: String? = nil, model: String? = nil, agent: String? = nil) {
        if let core { workSummary.coreStatus = WorkMonitorRedaction.text(core, limit: 60) }
        if let model { workSummary.modelStatus = WorkMonitorRedaction.text(model, limit: 60) }
        if let agent { workSummary.agentStatus = WorkMonitorRedaction.text(agent, limit: 60) }
        publishWorkMonitor()
    }

    private func setWorkCurrent(
        action: String,
        target: String,
        targetPath: String? = nil,
        purpose: String,
        activity: String,
        stage: String? = nil,
        status: String? = nil
    ) {
        workSummary.actionType = WorkMonitorRedaction.text(action, limit: 40)
        workSummary.target = WorkMonitorRedaction.text(target, limit: 180)
        workSummary.targetPath = targetPath.map { WorkMonitorRedaction.text($0, limit: 180) }
        workSummary.purpose = WorkMonitorRedaction.text(purpose, limit: 300)
        workSummary.activity = WorkMonitorRedaction.text(activity, limit: 300)
        if let stage { workSummary.currentStage = stage }
        if let status { workSummary.status = status }
        publishWorkMonitor()
    }

    private func addWorkRecent(
        _ title: String,
        state: WorkMonitorItemState = .success,
        detail: String? = nil
    ) {
        let safeTitle = WorkMonitorRedaction.text(title, limit: 180)
        guard !safeTitle.isEmpty else { return }
        if let first = workSummary.recentActivities.first,
           first.title == safeTitle,
           first.state == state {
            return
        }
        workSummary.recentActivities.insert(
            WorkRecentActivity(state: state, title: safeTitle, detail: detail.map { WorkMonitorRedaction.text($0, limit: 120) }),
            at: 0
        )
        workSummary.recentActivities = Array(workSummary.recentActivities.prefix(5))
        publishWorkMonitor()
    }

    private func updateWorkMonitorForTool(title: String, status: String, detail: String?, session: ChatSession) {
        let action = workAction(for: title)
        let targetInfo = workTarget(for: title, detail: detail, projectPath: session.projectPath)
        let stage = workStage(for: action)
        let running = !status.localizedCaseInsensitiveContains("complete")
            && !status.localizedCaseInsensitiveContains("fail")
        let failed = status.localizedCaseInsensitiveContains("fail")
        let activity: String
        if failed {
            activity = "当前操作失败，等待处理"
        } else if running {
            activity = "正在\(action) \(targetInfo.target)"
        } else {
            activity = "已完成\(action) \(targetInfo.target)"
        }
        setWorkCurrent(
            action: action,
            target: targetInfo.target,
            targetPath: targetInfo.path,
            purpose: workPurpose(for: action),
            activity: activity,
            stage: stage,
            status: failed ? "任务失败" : "正在工作"
        )
        if let path = targetInfo.path,
           ["修改", "创建", "删除"].contains(action) {
            let marker = action == "创建" ? "A" : action == "删除" ? "D" : "M"
            let file = WorkFileActivity(marker: marker, name: targetInfo.target, path: path)
            if !workSummary.files.contains(where: { $0.name == file.name && $0.marker == file.marker }) {
                workSummary.files.insert(file, at: 0)
                workSummary.files = Array(workSummary.files.prefix(12))
            }
        }
        if failed {
            addWorkRecent("\(action)未完成", state: .failed, detail: targetInfo.target)
        } else if !running {
            addWorkRecent("已完成\(action)\(targetInfo.target)", state: .success)
        }
        updateWorkStages()
    }

    private func workAction(for title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("browser") || lowered.contains("visual") { return "浏览器验证" }
        if lowered.contains("github") || lowered.contains("pull request") || lowered.contains("workflow") { return "GitHub" }
        if lowered.contains("read") || lowered.contains("cat") { return "读取" }
        if lowered.contains("search") || lowered.contains("grep") || lowered.contains("find") { return "搜索" }
        if lowered.contains("edit") || lowered.contains("write") || lowered.contains("patch") { return "修改" }
        if lowered.contains("create") || lowered.contains("touch") { return "创建" }
        if lowered.contains("delete") || lowered.contains("remove") { return "删除" }
        if lowered.contains("test") || lowered.contains("check") { return "验证" }
        if lowered.contains("build") || lowered.contains("compile") { return "构建" }
        if lowered.contains("bash") || lowered.contains("command") || lowered.contains("terminal") || lowered.contains("shell") { return "运行" }
        return "分析"
    }

    private func workStage(for action: String) -> String {
        switch action {
        case "修改", "创建", "删除", "运行": return "Builder"
        case "验证", "构建", "浏览器验证": return "Verifier"
        case "GitHub": return "Verifier"
        default: return "Architect"
        }
    }

    private func workPurpose(for action: String) -> String {
        switch action {
        case "读取", "搜索", "分析": return "建立任务所需的项目上下文，确认修改范围。"
        case "修改", "创建", "删除": return "把任务要求落实到项目文件，同时保持变更范围可审计。"
        case "运行": return "执行安全、可追踪的项目命令，获得真实结果。"
        case "验证", "构建": return "确认当前修改通过项目定义的验证门。"
        case "浏览器验证": return "检查页面布局、Console、Network 和响应式结果。"
        case "GitHub": return "同步公开的 Issue、PR 或 CI 状态，不展示凭据和原始参数。"
        default: return "推进当前任务并为下一阶段准备结果。"
        }
    }

    private func workTarget(for title: String, detail: String?, projectPath: String) -> (target: String, path: String?) {
        let combined = WorkMonitorRedaction.text([title, detail ?? ""].joined(separator: " "), limit: 600)
        let rawCandidates = combined.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == "(" || $0 == ")" || $0 == "[" || $0 == "]" })
        let fileExtensions = [".swift", ".rs", ".ts", ".tsx", ".js", ".json", ".toml", ".md", ".cjs", ".py", ".go"]
        if let raw = rawCandidates.first(where: { candidate in
            let value = String(candidate).trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
            return fileExtensions.contains(where: { value.lowercased().contains($0) })
        }) {
            var path = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
            if path.hasPrefix(projectPath + "/") { path = String(path.dropFirst(projectPath.count + 1)) }
            if path.hasPrefix("/") { path = URL(fileURLWithPath: path).lastPathComponent }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (name.isEmpty ? "项目文件" : name, path.isEmpty ? nil : path)
        }
        let lowered = combined.lowercased()
        if lowered.contains("github") || lowered.contains("workflow") { return ("GitHub CI", nil) }
        if lowered.contains("browser") || lowered.contains("visual") { return ("Browser Verification", nil) }
        if lowered.contains("project intelligence") || lowered.contains("context") { return ("Project Intelligence", nil) }
        if lowered.contains("test") || lowered.contains("check") { return ("项目验证", nil) }
        return (workAction(for: title) == "运行" ? "项目命令" : "项目上下文", nil)
    }

    private func updateWorkStages(from snapshot: AgentPipelineSnapshot? = nil) {
        let source = snapshot ?? pipeline.snapshot
        workSummary.stages = AgentStageName.allCases.map { stage in
            let state = source.states[stage] ?? .waiting
            switch state {
            case .active:
                return WorkStageDisplay(name: stage.rawValue, state: .active, detail: "正在工作")
            case .passed:
                return WorkStageDisplay(name: stage.rawValue, state: .success, detail: "已完成")
            case .failed:
                return WorkStageDisplay(name: stage.rawValue, state: .failed, detail: "失败")
            case .skipped:
                return WorkStageDisplay(name: stage.rawValue, state: .warning, detail: "跳过")
            case .waiting:
                return WorkStageDisplay(name: stage.rawValue, state: .pending, detail: "等待")
            }
        }
        if let active = workSummary.stages.first(where: { $0.state == .active }) {
            workSummary.currentStage = active.name
        }
        publishWorkMonitor()
    }

    private func updateWorkVerification(_ report: VerificationReport) {
        workSummary.verificationItems = report.checks.map { check in
            let state: WorkMonitorItemState
            let status: String
            switch check.status {
            case .pass: state = .success; status = "PASS"
            case .fail: state = .failed; status = "FAIL"
            case .skipped: state = .pending; status = "SKIPPED"
            }
            return WorkVerificationItem(
                name: WorkMonitorRedaction.text(check.name, limit: 100),
                state: state,
                statusText: status,
                detail: check.reason.map { WorkMonitorRedaction.text($0, limit: 120) }
            )
        }
        if !workSummary.verificationItems.contains(where: { $0.name == "Reviewer" }) {
            workSummary.verificationItems.append(WorkVerificationItem(name: "Reviewer", state: .pending, statusText: "等待", detail: nil))
        }
        publishWorkMonitor()
    }

    private func updateWorkVerificationPlan(projectPath: String) {
        var items = VerificationGate.plannedChecks(projectPath: projectPath).map { name, _, reason in
            WorkVerificationItem(
                name: WorkMonitorRedaction.text(name, limit: 100),
                state: .pending,
                statusText: reason == nil ? "等待" : "SKIPPED",
                detail: reason.map { WorkMonitorRedaction.text($0, limit: 120) }
            )
        }
        items.append(WorkVerificationItem(name: "Browser Verify", state: .pending, statusText: "未开始", detail: nil))
        items.append(WorkVerificationItem(name: "Reviewer", state: .pending, statusText: "等待", detail: nil))
        workSummary.verificationItems = items
        publishWorkMonitor()
    }

    private func updateWorkGitHub(_ snapshot: GitHubWorkflowSnapshot) {
        guard let metadata = snapshot.metadata else {
            workSummary.github = nil
            publishWorkMonitor()
            return
        }
        let workflow = metadata.workflowState
        let state: WorkMonitorItemState
        switch workflow {
        case .waitingCI, .preparing, .planning, .building, .verifying, .reviewing, .repairingCI:
            state = .active
        case .readyForHumanMerge, .mergedByHuman:
            state = .success
        case .failed, .ciFailed, .remoteSyncFailed, .unauthorized, .rateLimited, .blocked, .interrupted:
            state = .failed
        case .cancelled:
            state = .warning
        default:
            state = .pending
        }
        let ci = metadata.ciLastObservedState?.rawValue ?? workflow.rawValue
        workSummary.github = WorkGitHubSummary(
            repository: metadata.githubRepository?.fullName,
            issue: metadata.issueNumber.map { "#\($0) \(metadata.issueTitle ?? "")" }.map { WorkMonitorRedaction.text($0, limit: 120) },
            branch: metadata.taskBranch.map { WorkMonitorRedaction.text($0, limit: 120) },
            pullRequest: metadata.pullRequestNumber.map { "#\($0) \(metadata.pullRequestRef ?? "")" },
            ci: WorkMonitorRedaction.text(ci, limit: 100),
            state: state
        )
        publishWorkMonitor()
    }

    func resetLayout() {
        split.resetLayout()
        guard let window = view.window else { return }
        let size = NSSize(width: AppDelegate.defaultWindowWidth, height: AppDelegate.defaultWindowHeight)
        onRequestWindowSize?(size)
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var selectedSession: ChatSession? {
        guard let selectedID else { return nil }
        return store.sessions.first { $0.id == selectedID }
    }

    func refreshModelState() {
        guard let session = selectedSession else { return }
        applySessionState(session)
    }

    private func latestSystemError(in session: ChatSession) -> String? {
        guard let message = session.messages.last, message.role == .system else { return nil }
        return message.content
    }

    /// Classify actionable system failures so a late, more-specific error
    /// cannot leave a stale cancellation card immediately above it.  Runner
    /// termination and API rejection can arrive back-to-back; they describe
    /// one failed task, not two independent failures.
    private func systemErrorKind(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("api 配置") || lowered.contains("api key") || lowered.contains("密钥") || lowered.contains("401") || lowered.contains("unauthorized") {
            return "model"
        }
        if lowered.contains("停止") || lowered.contains("取消") || lowered.contains("cancel") {
            return "cancelled"
        }
        if lowered.contains("core") || lowered.contains("nexus 运行") || lowered.contains("编码代理") {
            return "core"
        }
        if lowered.contains("网络") || lowered.contains("连接") || lowered.contains("超时") || lowered.contains("timeout") {
            return "network"
        }
        if lowered.contains("验证失败") || lowered.contains("测试失败") {
            return "verification"
        }
        return "generic"
    }

    private func modelState(for session: ChatSession) -> ModelState {
        let configuration = NexusConfiguration.shared
        guard configuration.hasAPIKey else { return .missingKey }
        let model = configuration.value(named: "model", inSection: "model.openai-coding") ?? ""
        let endpoint = configuration.value(named: "base_url", inSection: "model.openai-coding") ?? ""
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: endpoint),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .configurationError
        }
        guard let error = latestSystemError(in: session)?.lowercased() else { return .ready }
        if error.contains("密钥") || error.contains("api key") || error.contains("unauthorized") || error.contains("401") {
            return .unauthorized
        }
        if error.contains("429") || error.contains("额度") || error.contains("频繁") {
            return .rateLimited
        }
        if error.contains("网络") || error.contains("连接") || error.contains("超时") || error.contains("timeout") {
            return .offline
        }
        return .ready
    }

    private func applySessionState(_ session: ChatSession) {
        defer {
            workSummary.modelStatus = modelState(for: session).monitorLabel
            if BackendLocator.wrapperURL == nil {
                workSummary.coreStatus = "Disconnected"
            } else if workSummary.coreStatus.isEmpty {
                workSummary.coreStatus = "Ready"
            }
            if activeTransaction == nil {
                workSummary.agentStatus = "Agent 空闲"
            }
            publishWorkMonitor()
        }
        guard BackendLocator.wrapperURL != nil else {
            chat.setStatus("Core disconnected", color: Palette.error)
            bottomBar.setCoreStatus("Core 已断开", color: Palette.error)
            bottomBar.setModelStatus("模型状态未知", color: Palette.secondaryText)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(false)
            chat.setAgentStage("Idle")
            return
        }
        bottomBar.setCoreStatus("Rust Core", color: Palette.success)
        if let error = latestSystemError(in: session),
           error.contains("没有找到 Nexus") || error.contains("无法启动 Nexus") {
            chat.setStatus("Core disconnected", color: Palette.error)
            bottomBar.setCoreStatus("Core 已断开", color: Palette.error)
            bottomBar.setModelStatus("模型状态未知", color: Palette.secondaryText)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(false)
            chat.setAgentStage("Idle")
            return
        }
        let state = modelState(for: session)
        if let error = latestSystemError(in: session), state == .ready {
            let cancelled = error.contains("停止") || error.localizedCaseInsensitiveContains("cancel")
            chat.setStatus(cancelled ? "已取消" : "任务失败", color: cancelled ? Palette.warning : Palette.error)
            bottomBar.setModelStatus("模型就绪", color: Palette.success)
            bottomBar.setAgentStatus(cancelled ? "Agent 已取消" : "Agent 失败", color: cancelled ? Palette.warning : Palette.error)
            chat.composer.setModelConfigured(true)
            chat.setAgentStage(cancelled ? "Idle" : "Failed")
            return
        }

        switch state {
        case .ready:
            chat.setStatus("● Agent Idle", color: Palette.success)
            bottomBar.setModelStatus("模型就绪", color: Palette.success)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(true)
            chat.setAgentStage("Idle")
        case .missingKey, .configurationError, .unauthorized:
            chat.setStatus("API 配置异常", color: Palette.warning)
            bottomBar.setModelStatus("模型配置异常", color: Palette.warning)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(false)
            chat.setAgentStage("Idle")
        case .rateLimited:
            chat.setStatus("模型请求受限", color: Palette.warning)
            bottomBar.setModelStatus("模型请求受限", color: Palette.warning)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(false)
            chat.setAgentStage("Idle")
        case .offline:
            chat.setStatus("模型接口离线", color: Palette.warning)
            bottomBar.setModelStatus("模型接口离线", color: Palette.warning)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            chat.composer.setModelConfigured(false)
            chat.setAgentStage("Idle")
        }
    }

    private func refreshSidebar() {
        sidebar.allSessionsValue = store.sessions
        sidebar.select(id: selectedID)
    }

    private func defaultProjectPath() -> String {
        if let saved = UserDefaults.standard.string(forKey: "默认项目目录"),
           FileManager.default.fileExists(atPath: saved) {
            return saved
        }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "NexusDefaultProjectPath") as? String,
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.path
    }

    private func newTask() {
        guard !runner.isRunning else {
            chat.setStatus("请先停止当前任务", color: Palette.warning)
            return
        }
        let session = store.create(projectPath: defaultProjectPath())
        selectedID = session.id
        sidebar.clearSearch()
        refreshSidebar()
        chat.display(session: session)
        workspacePanel.projectPath = session.projectPath
        resetWorkMonitor(for: session)
        applySessionState(session)
        chat.composer.focus()
    }

    private func select(id: UUID) {
        guard !runner.isRunning || id == selectedID else {
            chat.setStatus("任务运行中，停止后可切换", color: Palette.warning)
            sidebar.select(id: selectedID)
            return
        }
        guard let session = store.sessions.first(where: { $0.id == id }) else { return }
        selectedID = id
        sidebar.select(id: id)
        chat.display(session: session)
        workspacePanel.projectPath = session.projectPath
        resetWorkMonitor(for: session)
        applySessionState(session)
    }

    private func delete(id: UUID) {
        guard !runner.isRunning else { return }
        store.remove(id: id)
        if selectedID == id {
            selectedID = nil
            if let next = store.sessions.first {
                select(id: next.id)
            } else {
                newTask()
                return
            }
        }
        refreshSidebar()
    }

    private func chooseProject() {
        guard !runner.isRunning, var session = selectedSession else { return }
        let panel = NSOpenPanel()
        panel.title = "选择项目文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: session.projectPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        session.projectPath = url.path
        session.backendSessionID = UUID().uuidString.lowercased()
        session.backendCreated = false
        session.updatedAt = Date()
        store.update(session)
        UserDefaults.standard.set(url.path, forKey: "默认项目目录")
        refreshSidebar()
        chat.display(session: session)
        workspacePanel.projectPath = session.projectPath
        resetWorkMonitor(for: session)
        chat.setStatus("项目已切换", color: Palette.success)
    }

    private func openSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onSaved = { [weak self] in
                guard let self else { return }
                if let session = self.selectedSession {
                    self.applySessionState(session)
                } else {
                    self.chat.setStatus("设置已保存", color: Palette.success)
                }
            }
            controller.onResetLayout = { [weak self] in
                self?.resetLayout()
            }
            settingsController = controller
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWorkspace(segment: Int) {
        guard let session = selectedSession else { return }
        workspacePanel.projectPath = session.projectPath
        workspacePanel.isHidden = false
        workspacePanel.select(segment: segment)
        view.window?.setFrame(
            NSRect(
                origin: view.window?.frame.origin ?? .zero,
                size: NSSize(
                    width: max(view.window?.frame.width ?? 0, 1120),
                    height: view.window?.frame.height ?? 720
                )
            ),
            display: true,
            animate: true
        )
    }

    private func startBrowserVerificationFromWorkspace() {
        guard !browserVerificationInFlight, let session = selectedSession else { return }
        browserVerificationInFlight = true
        workspacePanel.showBrowserVerificationStatus("浏览器验证\n\n正在启动本地开发服务器…")
        chat.setStatus("● 浏览器验证 · 正在启动", color: Palette.accent)
        bottomBar.setAgentStatus("浏览器验证", color: Palette.accent)
        setWorkCurrent(
            action: "浏览器验证",
            target: "Browser Verification",
            purpose: "检查页面布局、Console、Network 和响应式结果。",
            activity: "正在启动本地浏览器验证",
            stage: "Verifier",
            status: "正在验证"
        )
        browserVerification.verify(
            projectPath: session.projectPath,
            taskID: "manual-\(UUID().uuidString.lowercased())",
            projectID: nil,
            viewport: .desktop
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.browserVerificationInFlight = false
                self.workspacePanel.showBrowserVerificationResult(result)
                let passed = result.status == .passed
                self.addWorkRecent(
                    passed ? "浏览器验证已完成" : "浏览器验证未通过",
                    state: passed ? .success : .failed,
                    detail: result.summary
                )
                self.setWorkCurrent(
                    action: "浏览器验证",
                    target: "Browser Verification",
                    purpose: "检查页面布局、Console、Network 和响应式结果。",
                    activity: passed ? "浏览器验证已完成" : "浏览器验证未通过",
                    stage: "Verifier",
                    status: passed ? "已完成" : "验证失败"
                )
                self.chat.setStatus(passed ? "浏览器验证通过" : "浏览器验证\(result.status == .skipped ? "已跳过" : "未通过")", color: passed ? Palette.success : Palette.warning)
                self.bottomBar.setAgentStatus(passed ? "Agent 空闲" : "浏览器需处理", color: passed ? Palette.secondaryText : Palette.warning)
            }
        }
    }

    private func send(promptOverride: String? = nil, appendUserMessage: Bool = true) {
        guard !runner.isRunning, activeTransaction == nil, !checkpointInFlight,
              let session = selectedSession else { return }
        let prompt = (promptOverride ?? chat.composer.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: session.projectPath) else {
            chat.setStatus("项目目录不存在，请重新选择", color: NSColor.systemRed)
            setWorkCurrent(
                action: "等待",
                target: "项目目录",
                purpose: "确认当前 Session 仍绑定到有效项目。",
                activity: "项目目录不存在",
                stage: "—",
                status: "需要处理"
            )
            chooseProject()
            return
        }
        guard NexusConfiguration.shared.hasAPIKey else {
            chat.setStatus("请先在设置中填写 DeepSeek API 密钥", color: Palette.warning)
            setWorkCurrent(
                action: "等待",
                target: "模型配置",
                purpose: "配置模型凭据后才能启动 Agent 任务。",
                activity: "等待完成模型配置",
                stage: "—",
                status: "模型配置异常"
            )
            openSettings()
            return
        }
        guard let approval = requestTaskApproval() else { return }

        // A project snapshot can traverse thousands of files, especially when
        // the project lives on the external development volume. Keep all of
        // that file-system work off the AppKit thread so the approval action
        // closes immediately and the user sees progress instead of a frozen UI.
        checkpointInFlight = true
        chat.composer.setRunning(true)
        chat.setStatus("正在创建任务快照…", color: Palette.accent)
        bottomBar.setAgentStatus("准备任务", color: Palette.accent)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let checkpoint = try CheckpointManager.shared.create(projectPath: session.projectPath)
                DispatchQueue.main.async {
                    guard let self, self.checkpointInFlight else { return }
                    self.checkpointInFlight = false
                    self.beginTask(
                        prompt: prompt,
                        session: session,
                        approval: approval,
                        checkpoint: checkpoint,
                        appendUserMessage: appendUserMessage
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.checkpointInFlight else { return }
                    self.checkpointInFlight = false
                    self.chat.composer.setRunning(false)
                    self.chat.setStatus("无法创建任务 checkpoint：\(error.localizedDescription)", color: Palette.error)
                    self.bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
                    self.setWorkCurrent(
                        action: "等待",
                        target: "任务 checkpoint",
                        purpose: "在执行任务前建立可回滚快照。",
                        activity: "无法创建 checkpoint",
                        stage: "—",
                        status: "任务失败"
                    )
                    self.addWorkRecent("checkpoint 创建失败", state: .failed)
                }
            }
        }
    }

    private func beginTask(
        prompt: String,
        session: ChatSession,
        approval: TaskApproval,
        checkpoint: CheckpointRecord,
        appendUserMessage: Bool
    ) {
        var session = session

        if appendUserMessage {
            let userMessage = ChatMessage(role: .user, content: prompt)
            session.messages.append(userMessage)
            if session.title == "新任务" {
                let compact = prompt.replacingOccurrences(of: "\n", with: " ")
                session.title = compact.count > 22 ? String(compact.prefix(22)) + "…" : compact
            }
            chat.addMessage(userMessage)
        }
        session.updatedAt = Date()
        store.update(session)
        refreshSidebar()
        chat.headerTitle.stringValue = session.title
        chat.composer.text = ""

        let assistant = ChatMessage(role: .assistant, content: "")
        session.messages.append(assistant)
        store.update(session)
        chat.addMessage(
            ChatMessage(id: assistant.id, role: .assistant, content: "Architect · Planning architecture", createdAt: assistant.createdAt),
            isStreaming: true
        )
        streamingText = ""
        pipeline.reset()
        browserRepairAttempts = 0
        _ = pipeline.start(.architect)
        var transaction = TaskTransaction(
            sessionId: session.id.uuidString.lowercased(),
            projectPath: session.projectPath,
            checkpointId: checkpoint.id
        )
        transaction.transition(to: .planning)
        transaction.agentStages.append("Architect: planning")
        transaction.pipeline = pipeline.snapshot
        transactionStore.upsert(transaction)
        activeTransaction = transaction
        finalization = TaskFinalizationCoordinator(taskID: transaction.taskId)
        activePrompt = prompt
        activeApproval = approval
        activeSessionID = session.id
        activeMessageID = assistant.id
        activeToolFailure = nil
        recovery.reset()
        workSummary = .idle
        workSummary.taskTitle = WorkMonitorRedaction.text(session.title, limit: 180)
        workSummary.projectName = URL(fileURLWithPath: session.projectPath).lastPathComponent
        workSummary.projectPath = session.projectPath
        workSummary.elapsedSince = transaction.startedAt
        workSummary.status = "正在工作"
        workSummary.currentStage = "Architect"
        workSummary.actionType = "分析"
        workSummary.target = "项目上下文"
        workSummary.purpose = "理解项目结构，规划安全且可验证的执行步骤。"
        workSummary.activity = "正在读取任务所需的项目上下文"
        workSummary.agentStatus = "Agent 正在工作"
        updateWorkStages()
        updateWorkVerificationPlan(projectPath: session.projectPath)
        addWorkRecent("已创建任务 checkpoint", state: .success, detail: "准备开始")
        publishWorkMonitor()
        chat.composer.setRunning(true)
        chat.setStatus("● Planning", color: Palette.accent)
        bottomBar.setAgentStatus("Planning", color: Palette.accent)
        chat.setAgentStage("Planning")

        let requestSession = session
        let projectContext = ProjectContextProvider.shared.promptContext(projectPath: session.projectPath, query: prompt)
        let runnerPrompt: String
        if projectContext.isEmpty {
            runnerPrompt = prompt
        } else {
            runnerPrompt = "\(prompt)\n\n\(projectContext)\n\nUse this bounded context as a starting point. Verify against the workspace before editing."
            updateTransaction { transaction in
                transaction.toolCalls.append("Project Intelligence: bounded context attached")
            }
        }
        startRunner(prompt: runnerPrompt, session: requestSession, approval: approval, messageID: assistant.id)
    }

    private func startRunner(prompt: String, session: ChatSession, approval: TaskApproval, messageID: UUID) {
        runner.send(prompt: prompt, session: session, approval: approval) { [weak self] event in
            // stdout is parsed on NexusRunner's serial background queue. All
            // state mutations and AppKit view updates must return to the main
            // thread, otherwise a successful Core response can be invisible
            // or make the composer appear stuck after approval.
            DispatchQueue.main.async {
                self?.handle(event: event, sessionID: session.id, messageID: messageID)
            }
        }
    }

    private func retryLastPrompt() {
        guard !runner.isRunning, activeTransaction == nil, !checkpointInFlight, let session = selectedSession,
              let prompt = session.messages.last(where: { $0.role == .user })?.content,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        send(promptOverride: prompt, appendUserMessage: false)
    }

    private func requestTaskApproval() -> TaskApproval? {
        let alert = NSAlert()
        alert.messageText = "允许 Nexus 执行这个任务吗？"
        alert.informativeText = "允许后，Nexus 可以在当前项目内读取和编辑文件、运行命令。沙盒仍会限制项目外的写入。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "允许本次任务")
        alert.addButton(withTitle: "仅分析，不修改")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .allowWorkspace
        case .alertSecondButtonReturn:
            return .readOnly
        default:
            return nil
        }
    }

    private func handle(event: RunnerEvent, sessionID: UUID, messageID: UUID) {
        guard var session = store.sessions.first(where: { $0.id == sessionID }) else { return }
        switch event {
        case .coreState(let state):
            handleCoreState(state, session: session, messageID: messageID)
        case .text(let chunk):
            recovery.reset()
            updateTransaction { transaction in
                if transaction.finalState == .planning { transaction.transition(to: .building) }
            }
            streamingText += chunk
            if let index = session.messages.firstIndex(where: { $0.id == messageID }) {
                session.messages[index].content = streamingText
                session.updatedAt = Date()
                store.update(session)
            }
            chat.updateStreamingText(streamingText)
            setWorkCurrent(
                action: "分析",
                target: "任务响应",
                purpose: "根据当前项目上下文准备可执行的修改与验证步骤。",
                activity: "正在整理 Agent 输出",
                stage: "Architect",
                status: "正在工作"
            )
        case .thought(let thought):
            recovery.reset()
            let short = thought.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = short.isEmpty ? "Thinking" : short
            chat.setStatus("● " + state, color: Palette.accent)
            bottomBar.setAgentStatus(state, color: Palette.accent)
            chat.setAgentStage(state.lowercased().contains("plan") ? "Planning" : "Thinking")
            updateTransaction { transaction in
                transaction.agentStages.append("Architect: \(state)")
            }
            setWorkCurrent(
                action: "分析",
                target: "任务计划",
                purpose: "将任务拆分为可验证的执行步骤，不展示模型内部推理。",
                activity: "正在分析任务并协调执行",
                stage: "Architect",
                status: "正在工作"
            )
        case .tool(let id, let title, let status, let detail):
            recovery.reset()
            let display = localizedToolTitle(title, status: status, detail: detail)
            if let index = session.messages.firstIndex(where: { $0.toolID == id }) {
                session.messages[index].content = display
                session.messages[index].toolStatus = status
            } else {
                session.messages.append(
                    ChatMessage(
                        role: .tool,
                        content: display,
                        toolID: id,
                        toolStatus: status
                    )
                )
            }
            session.updatedAt = Date()
            store.update(session)
            chat.display(session: session, streamingMessageID: messageID)
            let stage = agentStage(for: title)
            chat.setStatus("● " + stage.name, color: stage.color)
            bottomBar.setAgentStatus(stage.name, color: stage.color)
            chat.setAgentStage(stage.name)
            updatePipeline(for: stage.name, status: status)
            updateTransaction { transaction in
                let auditDetail = detail.map { " — \($0)" } ?? ""
                transaction.toolCalls.append("\(title): \(status)\(auditDetail)")
            }
            updateWorkMonitorForTool(title: title, status: status, detail: detail, session: session)
            if status.localizedCaseInsensitiveContains("fail") {
                let reason = detail ?? "工具执行失败，任务未完成。"
                activeToolFailure = localizedToolFailure(reason, action: title)
                chat.setStatus("工具执行失败", color: Palette.error)
                bottomBar.setAgentStatus("Agent 失败", color: Palette.error)
                chat.setAgentStage("Failed")
                updateTransaction { transaction in
                    transaction.transition(to: .failed)
                    transaction.agentStages.append("Tool failed: \(reason)")
                }
            }
        case .plan(let plan):
            recovery.reset()
            session.messages.append(
                ChatMessage(role: .tool, content: "计划已更新\n\(plan)")
            )
            session.updatedAt = Date()
            store.update(session)
            chat.display(session: session, streamingMessageID: messageID)
            chat.setStatus("● Planning", color: Palette.accent)
            bottomBar.setAgentStatus("Planning", color: Palette.accent)
            chat.setAgentStage("Planning")
            updateTransaction { transaction in
                transaction.agentStages.append("Architect: plan updated")
            }
            setWorkCurrent(
                action: "分析",
                target: "执行计划",
                purpose: "明确接下来的修改对象和验证步骤。",
                activity: "正在整理执行计划",
                stage: "Architect",
                status: "正在工作"
            )
            addWorkRecent("已更新执行计划", state: .success)
        case .ended(let backendID):
            // `end` is the only authoritative runtime completion signal.  A
            // browser/server callback may arrive before or after it, but a
            // duplicate/late end must never start a second verification run.
            guard finalization.runtimeEnded() else { return }
            updateTransaction { transaction in
                transaction.agentStages.append("Runtime: end received")
            }
            if let toolFailure = activeToolFailure {
                _ = finalization.fail(reason: "tool_failure")
                updateTransaction { transaction in
                    _ = transaction.transition(to: .failed)
                    transaction.agentStages.append("Task stopped after tool failure")
                }
                finishFailure(toolFailure, session: session, messageID: messageID)
                activeTransaction = nil
                clearActiveTask()
                verificationInFlight = false
                return
            }
            if let backendID, !backendID.isEmpty {
                session.backendSessionID = backendID
            }
            session.backendCreated = true
            session.updatedAt = Date()
            store.update(session)
            setWorkCurrent(
                action: "验证",
                target: "项目测试",
                purpose: "确认修改通过项目验证，再进入 Reviewer。",
                activity: "正在准备验证门",
                stage: "Verifier",
                status: "正在验证"
            )
            addWorkRecent("Agent 运行阶段已完成", state: .success)
            beginVerification(session: session, messageID: messageID)
        case .failed(let message, let cancellationSource):
            recovery.reset()
            if let source = cancellationSource, source != .unknown {
                guard finalization.requestCancel(source: source) else { return }
                updateTransaction { transaction in
                    _ = transaction.transition(to: .cancelled, cancellationSource: source)
                    transaction.agentStages.append("Task cancelled: \(source.rawValue)")
                }
            } else {
                guard finalization.fail(reason: message) else { return }
                updateTransaction { transaction in
                    _ = transaction.transition(to: .failed)
                }
            }
            setWorkCurrent(
                action: "等待",
                target: "任务结果",
                purpose: "保留失败原因，避免在验证未通过时误报完成。",
                activity: WorkMonitorRedaction.text(message, limit: 220),
                stage: "—",
                status: cancellationSource == nil ? "任务失败" : "已取消"
            )
            addWorkRecent(cancellationSource == nil ? "任务失败" : "任务已取消", state: cancellationSource == nil ? .failed : .warning, detail: message)
            finishFailure(message, session: session, messageID: messageID)
            activeTransaction = nil
            clearActiveTask()
            verificationInFlight = false
        }
    }

    private func handleCoreState(_ state: CoreState, session: ChatSession, messageID: UUID) {
        switch state {
        case .stopped:
            bottomBar.setCoreStatus("Core 已停止", color: Palette.secondaryText)
            chat.setStatus("Core 已停止", color: Palette.secondaryText)
            updateWorkMonitorRuntime(core: "Stopped", agent: "Agent 空闲")
        case .starting:
            bottomBar.setCoreStatus("Rust Core", color: Palette.warning)
            chat.setStatus("正在启动 Core", color: Palette.warning)
            setWorkCurrent(
                action: "恢复",
                target: "AI Dev One Core",
                purpose: "启动本地运行时，确保任务执行链恢复。",
                activity: "正在启动 Agent Runtime",
                stage: activeTransaction == nil ? "—" : workSummary.currentStage,
                status: "正在恢复"
            )
            updateWorkMonitorRuntime(core: "Starting")
        case .ready:
            bottomBar.setCoreStatus("Rust Core", color: Palette.success)
            updateWorkMonitorRuntime(core: "Ready")
            if activeTransaction == nil {
                chat.setStatus("Core 已恢复，可重新运行任务", color: Palette.success)
                bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
                workSummary.status = "空闲"
                workSummary.activity = "等待用户提交任务"
                workSummary.actionType = "等待"
                workSummary.target = "暂无活动"
                workSummary.currentStage = "—"
                updateWorkStages()
            }
        case .restarting:
            bottomBar.setCoreStatus("Core 重启中", color: Palette.warning)
            chat.setStatus("Core 正在恢复", color: Palette.warning)
            setWorkCurrent(
                action: "恢复",
                target: "AI Dev One Core",
                purpose: "重新连接运行时；当前任务不会自动重放。",
                activity: "正在重新启动 Agent Runtime",
                stage: activeTransaction == nil ? "—" : workSummary.currentStage,
                status: "正在恢复"
            )
            updateWorkMonitorRuntime(core: "Restarting")
        case .disconnected:
            bottomBar.setCoreStatus("Core 已断开", color: Palette.error)
            updateWorkMonitorRuntime(core: "Disconnected")
            if activeTransaction != nil {
                chat.setStatus("Core 已断开，任务已中断，正在恢复 Core", color: Palette.warning)
                setWorkCurrent(
                    action: "恢复",
                    target: "AI Dev One Core",
                    purpose: "保存中断状态，等待运行时恢复后由用户选择重试或回滚。",
                    activity: "Core 已断开，任务已中断",
                    stage: workSummary.currentStage,
                    status: "已中断"
                )
                addWorkRecent("Core 已断开，任务已中断", state: .warning)
                _ = finalization.interrupt(source: .coreCrash)
                updateTransaction { transaction in
                    _ = transaction.transition(to: .interrupted, cancellationSource: .coreCrash)
                    transaction.agentStages.append("Core disconnected")
                    transaction.pipeline = pipeline.snapshot
                }
                // Do not resend the old prompt. Persist interruption first,
                // then make the normal retry action available to the user.
                finishFailure("Core 已断开，当前任务已中断。Core 恢复后可重新运行任务。", session: session, messageID: messageID)
                activeTransaction = nil
                clearActiveTask()
                verificationInFlight = false
            } else {
                chat.setStatus("Core disconnected", color: Palette.error)
                setWorkCurrent(
                    action: "恢复",
                    target: "AI Dev One Core",
                    purpose: "等待用户重新启动本地运行时。",
                    activity: "Core 已断开",
                    stage: "—",
                    status: "Core 已断开"
                )
            }
            runner.scheduleAutomaticRecovery { [weak self] nextState in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.handleCoreState(nextState, session: session, messageID: messageID)
                }
            }
        case .failed:
            bottomBar.setCoreStatus("Core 失败", color: Palette.error)
            chat.setStatus("Core 无法恢复", color: Palette.error)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            setWorkCurrent(
                action: "恢复",
                target: "AI Dev One Core",
                purpose: "运行时恢复失败，需要用户重新启动 Core。",
                activity: "Core 无法恢复",
                stage: "—",
                status: "Core 无法恢复"
            )
            addWorkRecent("Core 无法恢复", state: .failed, detail: "可在底部状态栏重新启动")
            updateWorkMonitorRuntime(core: "Failed", agent: "Agent 空闲")
        }
    }

    private func beginVerification(session: ChatSession, messageID: UUID) {
        guard !verificationInFlight,
              finalization.runtimeEndReceived,
              !finalization.isTerminal,
              let transaction = activeTransaction,
              finalization.taskID == transaction.taskId else { return }
        verificationInFlight = true
        if pipeline.activeStage == .architect { _ = pipeline.pass(.architect) }
        if pipeline.activeStage == nil { _ = pipeline.start(.builder) }
        if pipeline.activeStage == .builder { _ = pipeline.pass(.builder) }
        if pipeline.activeStage == nil { _ = pipeline.start(.verifier) }
        updateTransaction { current in
            current.transition(to: .testing)
            current.agentStages.append("Verifier: testing")
            current.pipeline = pipeline.snapshot
        }
        updateWorkStages()
        updateWorkVerificationPlan(projectPath: session.projectPath)
        setWorkCurrent(
            action: "验证",
            target: "项目测试",
            purpose: "确认修改通过项目定义的 typecheck、lint、test 或 build 检查。",
            activity: "正在运行项目验证",
            stage: "Verifier",
            status: "正在验证"
        )
        addWorkRecent("Builder 已完成，Verifier 开始工作", state: .success)
        chat.setStatus("● Verifier · 正在验证", color: Palette.accent)
        bottomBar.setAgentStatus("Agent 运行中", color: Palette.accent)
        VerificationGate.evaluateAsync(projectPath: session.projectPath) { [weak self] report in
            guard let self else { return }
            guard self.activeTransaction?.taskId == transaction.taskId,
                  let latest = self.store.sessions.first(where: { $0.id == session.id }) else { return }
            self.updateTransaction { current in
                current.verification = report.checks
                current.pipeline = self.pipeline.snapshot
            }
            self.updateWorkVerification(report)
            self.setWorkCurrent(
                action: "验证",
                target: "项目测试",
                purpose: report.hasFailure ? "识别失败检查并阻止任务误报完成。" : "确认项目验证结果，再进入 Reviewer。",
                activity: report.hasFailure ? "项目验证发现失败项" : "项目验证已完成，准备 Reviewer",
                stage: "Verifier",
                status: report.hasFailure ? "验证失败" : "正在验证"
            )
            self.addWorkRecent(report.hasFailure ? "项目验证未通过" : "项目验证已完成", state: report.hasFailure ? .failed : .success, detail: "(report.checks.filter { $0.status == .pass }.count) 项通过")
            if report.hasFailure {
                _ = self.pipeline.fail(.verifier)
                self.updateTransaction { current in
                    current.pipeline = self.pipeline.snapshot
                    current.transition(to: .failed)
                }
                self.finishFailure("验证失败：请查看任务验证结果后修复问题。", session: latest, messageID: messageID)
                self.activeTransaction = nil
                self.clearActiveTask()
                self.verificationInFlight = false
                return
            }
            let needsBrowser = BrowserVerificationPlanner.shouldRun(
                projectPath: session.projectPath,
                prompt: self.activePrompt ?? "",
                transaction: transaction
            )
            if needsBrowser {
                self.browserMobileVerificationCompleted = false
                self.browserVerificationInFlight = true
                self.chat.setStatus("● 浏览器验证 · 正在启动本地页面", color: Palette.accent)
                self.bottomBar.setAgentStatus("浏览器验证", color: Palette.accent)
                self.workspacePanel.showBrowserVerificationStatus("浏览器验证\n\n正在启动本地开发服务器…")
                self.browserVerification.verify(
                    projectPath: session.projectPath,
                    taskID: transaction.taskId,
                    projectID: nil,
                    viewport: .desktop
                ) { [weak self] browserResult in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.browserVerificationInFlight = false
                        self.workspacePanel.showBrowserVerificationResult(browserResult)
                        self.setWorkCurrent(
                            action: "浏览器验证",
                            target: "Browser Verification",
                            purpose: "检查页面布局、Console、Network 和响应式结果。",
                            activity: browserResult.status == .passed ? "桌面视口验证已完成" : "桌面视口验证未通过",
                            stage: "Verifier",
                            status: browserResult.status == .passed ? "正在验证" : "验证失败"
                        )
                        self.addWorkRecent(
                            browserResult.status == .passed ? "Desktop 浏览器验证已完成" : "Desktop 浏览器验证未通过",
                            state: browserResult.status == .passed ? .success : .failed,
                            detail: browserResult.summary
                        )
                        self.finalization.browserCleanupCompleted()
                        self.updateTransaction { current in
                            current.verification.append(self.browserVerificationCheck(browserResult))
                            current.toolCalls.append("Browser Verification evidence: \(browserResult.verificationID)")
                            current.agentStages.append("Browser Verification: \(browserResult.status.rawValue)")
                        }
                        guard self.activeTransaction?.taskId == transaction.taskId,
                              let latestSession = self.store.sessions.first(where: { $0.id == session.id }) else { return }
                        if browserResult.hasBlockingFinding {
                            guard browserResult.status == .failed else {
                                _ = self.finalization.browserFailed()
                                self.updateTransaction { current in
                                    current.pipeline = self.pipeline.snapshot
                                    current.transition(to: .failed)
                                }
                                self.finishFailure("浏览器验证未完成：\(browserResult.summary)", session: latestSession, messageID: messageID)
                                self.activeTransaction = nil
                                self.clearActiveTask()
                                self.verificationInFlight = false
                                return
                            }
                            if self.browserRepairAttempts < 3 {
                                self.browserRepairAttempts += 1
                                self.verificationInFlight = false
                                self.pipeline.reset()
                                _ = self.pipeline.start(.architect)
                                _ = self.pipeline.pass(.architect)
                                _ = self.pipeline.start(.builder)
                                let details = browserResult.findings.prefix(8).map { "- \($0.message): \($0.detail ?? "")" }.joined(separator: "\n")
                                let repairPrompt = """
                                Browser Visual Verification 发现页面问题，请在当前项目中修复后重新验证（第 \(self.browserRepairAttempts)/3 轮）：
                                \(details)
                                只修复与页面运行、布局、Console 或资源加载相关的问题，完成后运行项目测试。
                                """
                                self.activePrompt = repairPrompt
                                self.updateTransaction { current in
                                    current.transition(to: .building)
                                    current.pipeline = self.pipeline.snapshot
                                    current.agentStages.append("Builder: browser fix loop \(self.browserRepairAttempts)/3")
                                }
                                self.chat.setStatus("● Builder · 正在修复浏览器问题", color: Palette.violet)
                                self.bottomBar.setAgentStatus("Builder 修复", color: Palette.violet)
                                self.startRunner(
                                    prompt: repairPrompt,
                                    session: latestSession,
                                    approval: self.activeApproval ?? .allowWorkspace,
                                    messageID: messageID
                                )
                                return
                            }
                            _ = self.pipeline.fail(.verifier)
                            _ = self.finalization.browserFailed()
                            self.updateTransaction { current in
                                current.pipeline = self.pipeline.snapshot
                                current.transition(to: .failed)
                            }
                            self.finishFailure("浏览器视觉验证失败：请查看 Workspace 中的验证证据。", session: latestSession, messageID: messageID)
                            self.activeTransaction = nil
                            self.clearActiveTask()
                            self.verificationInFlight = false
                            return
                        }
                        if !self.browserMobileVerificationCompleted {
                            self.startMobileBrowserVerification(
                                session: latestSession,
                                messageID: messageID,
                                report: report,
                                taskID: transaction.taskId
                            )
                            return
                        }
                        guard self.finalization.browserPassed() else { return }
                        self.finalizeVerification(session: latestSession, messageID: messageID, report: report)
                    }
                }
                return
            }
            self.verificationInFlight = false
            guard self.finalization.browserPassed() else { return }
            self.finalizeVerification(session: latest, messageID: messageID, report: report)
        }
    }

    /// Run the mobile viewport after the desktop viewport has passed.  This
    /// remains part of the same transaction and uses the same finalization
    /// guard, so a late runtime event or cancellation cannot complete it.
    private func startMobileBrowserVerification(
        session: ChatSession,
        messageID: UUID,
        report: VerificationReport,
        taskID: String
    ) {
        guard !browserMobileVerificationCompleted,
              activeTransaction?.taskId == taskID else { return }
        browserVerificationInFlight = true
        chat.setStatus("● 浏览器验证 · 移动端正在启动", color: Palette.accent)
        bottomBar.setAgentStatus("移动端验证", color: Palette.accent)
        workspacePanel.showBrowserVerificationStatus("浏览器验证（移动端）\n\n正在启动本地开发服务器…")
        browserVerification.verify(
            projectPath: session.projectPath,
            taskID: taskID,
            projectID: nil,
            viewport: .mobile
        ) { [weak self] browserResult in
            DispatchQueue.main.async {
                guard let self else { return }
                self.browserVerificationInFlight = false
                self.workspacePanel.showBrowserVerificationResult(browserResult)
                self.setWorkCurrent(
                    action: "浏览器验证",
                    target: "Browser Verification · Mobile",
                    purpose: "确认移动端视口没有布局溢出或阻塞性错误。",
                    activity: browserResult.status == .passed ? "移动视口验证已完成" : "移动视口验证未通过",
                    stage: "Verifier",
                    status: browserResult.status == .passed ? "正在验证" : "验证失败"
                )
                self.addWorkRecent(
                    browserResult.status == .passed ? "Mobile 浏览器验证已完成" : "Mobile 浏览器验证未通过",
                    state: browserResult.status == .passed ? .success : .failed,
                    detail: browserResult.summary
                )
                self.finalization.browserCleanupCompleted()
                self.updateTransaction { current in
                    current.verification.append(self.browserVerificationCheck(browserResult, viewport: .mobile))
                    current.toolCalls.append("Browser Verification 移动端 evidence: \(browserResult.verificationID)")
                    current.agentStages.append("Browser Verification 移动端: \(browserResult.status.rawValue)")
                }
                guard self.activeTransaction?.taskId == taskID,
                      let latestSession = self.store.sessions.first(where: { $0.id == session.id }) else { return }
                guard !browserResult.hasBlockingFinding else {
                    _ = self.finalization.browserFailed()
                    self.updateTransaction { current in
                        current.pipeline = self.pipeline.snapshot
                        current.transition(to: .failed)
                    }
                    self.finishFailure("移动端浏览器验证失败：\(browserResult.summary)", session: latestSession, messageID: messageID)
                    self.activeTransaction = nil
                    self.clearActiveTask()
                    return
                }
                self.browserMobileVerificationCompleted = true
                guard self.finalization.browserPassed() else { return }
                self.finalizeVerification(session: latestSession, messageID: messageID, report: report)
            }
        }
    }

    private func browserVerificationCheck(_ result: BrowserVerificationResult, viewport: BrowserViewport? = nil) -> VerificationCheck {
        let status: VerificationStatus
        switch result.status {
        case .passed: status = .pass
        case .skipped: status = .skipped
        default: status = .fail
        }
        let duration = max(0, result.endedAt.timeIntervalSince(result.startedAt))
        return VerificationCheck(
            name: viewport.map { $0 == .mobile ? "Browser Visual Verification (Mobile)" : "Browser Visual Verification (Desktop)" } ?? "Browser Visual Verification",
            command: result.devServerURL,
            status: status,
            reason: result.status == .passed ? nil : result.summary,
            output: "\(result.summary)\n截图：\(result.screenshots.first?.path ?? "无")\nConsole \(result.consoleMessages.count) errors / Network \(result.failedRequests.count) failed / Layout \(result.layoutFindings.count) findings",
            duration: duration
        )
    }

    private func finalizeVerification(session: ChatSession, messageID: UUID, report: VerificationReport) {
        verificationInFlight = false
        guard finalization.runtimeEndReceived,
              finalization.browserVerificationPassed,
              !finalization.isTerminal,
              finalization.startReviewer() else { return }
        _ = pipeline.pass(.verifier)
        if pipeline.activeStage == nil { _ = pipeline.start(.reviewer) }
        if pipeline.activeStage == .reviewer { _ = pipeline.pass(.reviewer) }
        let pipelinePassed = pipeline.canComplete
        _ = finalization.finishReviewer(passed: pipelinePassed)
        updateWorkStages()
        setWorkCurrent(
            action: "验证",
            target: "Reviewer",
            purpose: "完成最终审查，只有 Verifier 和 Reviewer 都通过才允许任务完成。",
            activity: pipelinePassed ? "Reviewer 已完成最终审查" : "Reviewer 未通过",
            stage: "Reviewer",
            status: pipelinePassed ? "已完成" : "任务失败"
        )
        addWorkRecent(pipelinePassed ? "Reviewer 审查已通过" : "Reviewer 审查未通过", state: pipelinePassed ? .success : .failed)
        updateTransaction { current in
            current.pipeline = pipeline.snapshot
            current.agentStages.append("Reviewer: review passed")
            current.transition(to: pipelinePassed ? .completed : .failed)
        }
        guard pipelinePassed else {
            _ = finalization.fail(reason: "reviewer_failed")
            finishFailure("Agent 流水线未完成 Verifier/Reviewer 验证。", session: session, messageID: messageID)
            activeTransaction = nil
            clearActiveTask()
            return
        }
        var latest = session
        if let index = latest.messages.firstIndex(where: { $0.id == messageID }), latest.messages[index].content.isEmpty {
            latest.messages[index].content = report.checks.contains(where: { $0.status == .pass })
                ? "任务已完成，验证通过。"
                : "任务已完成，验证项均已跳过。"
        }
        latest.updatedAt = Date()
        store.update(latest)
        finishRun(status: "已完成", color: Palette.success)
        activeTransaction = nil
        clearActiveTask()
    }

    private func finishFailure(_ message: String, session: ChatSession, messageID: UUID) {
        recordProjectKnowledge()
        var latest = session
        latest.messages.removeAll { $0.id == messageID && $0.content.isEmpty }
        let newKind = systemErrorKind(message)
        if let previousIndex = latest.messages.lastIndex(where: { $0.role == .system }) {
            let previousKind = systemErrorKind(latest.messages[previousIndex].content)
            if newKind == "model", previousKind == "cancelled" {
                // A process exit can report "任务已停止" just before the
                // backend exposes the actual 401/configuration failure.
                // Keep only the actionable model error card.
                latest.messages.remove(at: previousIndex)
            } else if newKind == previousKind {
                latest.messages[previousIndex].content = message
            } else {
                latest.messages.append(ChatMessage(role: .system, content: message))
            }
        } else {
            latest.messages.append(ChatMessage(role: .system, content: message))
        }
        latest.updatedAt = Date()
        store.update(latest)
        chat.finishStreaming()
        chat.display(session: latest)
        chat.composer.setRunning(false)
        applySessionState(latest)
        refreshSidebar()
        if !workspacePanel.isHidden { workspacePanel.refresh() }
        chat.composer.focus()
    }

    private func updateTransaction(_ update: (inout TaskTransaction) -> Void) {
        guard var transaction = activeTransaction else { return }
        update(&transaction)
        activeTransaction = transaction
        transactionStore.upsert(transaction)
        updateWorkStages(from: transaction.pipeline)
        if transaction.github != nil {
            let snapshot = GitHubWorkflowSnapshot(transaction: transaction, restoring: false, error: nil, activePollerCount: githubWorkflowCoordinator.activePollerCount)
            updateWorkGitHub(snapshot)
        }
        // GitHub CI is a long-lived task boundary.  Once the runtime records
        // a waiting_ci transaction, hand the same persisted object to the
        // app-level coordinator so polling survives view refreshes and a
        // subsequent cold start.  Non-GitHub tasks remain on the existing
        // transaction path.
        if transaction.github?.workflowState == .waitingCI {
            githubWorkflowCoordinator.monitor(transaction)
        }
    }

    private func clearActiveTask() {
        activePrompt = nil
        activeApproval = nil
        activeSessionID = nil
        activeMessageID = nil
        activeToolFailure = nil
    }

    private func updatePipeline(for stageName: String, status: String) {
        let lowered = stageName.lowercased()
        let target: AgentStageName
        if lowered.contains("test") { target = .verifier }
        else if lowered.contains("review") || lowered.contains("search") { target = .reviewer }
        else if lowered.contains("edit") || lowered.contains("run") { target = .builder }
        else { target = .architect }
        if target != .architect, pipeline.activeStage == .architect { _ = pipeline.pass(.architect) }
        if target == .verifier, pipeline.activeStage == .builder { _ = pipeline.pass(.builder) }
        if target == .reviewer, pipeline.activeStage == .builder { _ = pipeline.pass(.builder); _ = pipeline.start(.verifier); _ = pipeline.pass(.verifier) }
        if pipeline.activeStage == nil { _ = pipeline.start(target) }
        if status.lowercased().contains("complete"), pipeline.activeStage == target { _ = pipeline.pass(target) }
        updateTransaction { transaction in
            transaction.pipeline = pipeline.snapshot
            transaction.agentStages.append("\(target.rawValue): \(status)")
        }
    }

    private func finishRun(status: String, color: NSColor) {
        recordProjectKnowledge(finalState: status == "已完成" ? "completed" : nil)
        workSummary.status = status
        workSummary.actionType = status == "已完成" ? "验证" : "等待"
        workSummary.target = status == "已完成" ? "任务结果" : "暂无活动"
        workSummary.activity = status == "已完成" ? "任务已完成，验证通过" : status
        workSummary.purpose = status == "已完成" ? "保留真实验证结果，便于从 Work Monitor 快速复盘。" : "等待下一步操作。"
        workSummary.agentStatus = status == "已完成" ? "Agent 完成" : status
        updateWorkStages()
        addWorkRecent(status == "已完成" ? "任务已完成" : status, state: status == "已完成" ? .success : .warning)
        chat.finishStreaming()
        chat.composer.setRunning(false)
        chat.setStatus(status, color: color)
        bottomBar.setModelStatus("模型就绪", color: Palette.success)
        bottomBar.setAgentStatus(status == "已完成" ? "Agent 完成" : status, color: color)
        chat.setAgentStage(status == "已完成" ? "Completed" : "Reviewing")
        refreshSidebar()
        if !workspacePanel.isHidden {
            workspacePanel.refresh()
        }
        chat.composer.focus()
    }

    private func recordProjectKnowledge(finalState: String? = nil) {
        guard let transaction = activeTransaction else { return }
        let summary = redactKnowledge(activePrompt ?? "")
        let checks = transaction.verification.map { check in
            "\(redactKnowledge(check.name)): \(check.status.rawValue)"
        }
        let knowledge = TaskKnowledge(
            taskId: transaction.taskId,
            summary: summary.isEmpty ? "未命名任务" : summary,
            filesRead: transaction.toolCalls.prefix(80).map(redactKnowledge),
            filesChanged: transaction.fileChanges.prefix(80).map(redactKnowledge),
            symbolsChanged: [],
            verification: checks,
            finalState: finalState ?? transaction.finalState.rawValue,
            recordedAt: Date()
        )
        ProjectIntelligenceService.shared.recordTaskKnowledge(knowledge, projectPath: transaction.projectPath)
    }

    private func redactKnowledge(_ value: String) -> String {
        var result = value
        let patterns: [(String, String)] = [
            (#"(?i)sk-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
            (#"(?i)xai-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+\-/=]+"#, "$1<redacted-key>"),
            (#"(?i)(api[_-]?key\s*[=:]\s*)[^\s,&]+"#, "$1<redacted-key>"),
        ]
        for (pattern, replacement) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result = expression.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: replacement
            )
        }
        return String(result.prefix(600))
    }

    private func stop() {
        if checkpointInFlight {
            checkpointInFlight = false
            chat.composer.setRunning(false)
            chat.setStatus("任务已取消", color: Palette.secondaryText)
            bottomBar.setAgentStatus("Agent 空闲", color: Palette.secondaryText)
            setWorkCurrent(
                action: "等待",
                target: "任务 checkpoint",
                purpose: "取消尚未开始执行的任务，不留下半成品状态。",
                activity: "任务已取消",
                stage: "—",
                status: "已取消"
            )
            addWorkRecent("任务已取消", state: .warning)
            return
        }
        guard activeTransaction != nil,
              let session = selectedSession,
              let messageID = activeMessageID else {
            runner.stop(source: .user)
            return
        }
        // Cancellation is an explicit user action.  Mark the parent task
        // terminal before stopping the child process so a late runtime `end`
        // or tool callback cannot resurrect it as completed.
        guard finalization.requestCancel(source: .user) else { return }
        updateTransaction { current in
            _ = current.transition(to: .cancelled, cancellationSource: .user)
            current.agentStages.append("Task cancelled: user")
            current.pipeline = pipeline.snapshot
        }
        chat.setStatus("正在停止", color: Palette.warning)
        setWorkCurrent(
            action: "等待",
            target: "当前任务",
            purpose: "停止后保留事务状态，避免后续事件把任务误报为完成。",
            activity: "正在停止任务",
            stage: workSummary.currentStage,
            status: "正在停止"
        )
        browserVerification.cancel()
        finishFailure("任务已停止。", session: session, messageID: messageID)
        activeTransaction = nil
        clearActiveTask()
        verificationInFlight = false
        runner.stop(source: .user)
    }

    private func localizedToolTitle(_ title: String, status: String, detail: String? = nil) -> String {
        let lowered = title.lowercased()
        let action: String
        if lowered.contains("read") {
            action = "读取"
        } else if lowered.contains("edit") || lowered.contains("write") {
            action = "编辑"
        } else if lowered.contains("bash") || lowered.contains("command") || lowered.contains("terminal") {
            action = "运行命令"
        } else if lowered.contains("search") || lowered.contains("grep") {
            action = "搜索"
        } else if lowered.contains("test") {
            action = "运行测试"
        } else {
            action = title
        }
        let loweredStatus = status.lowercased()
        if loweredStatus.contains("complete") {
            return "已完成：\(action)"
        }
        if loweredStatus.contains("fail") {
            return localizedToolFailure(detail ?? "工具执行失败", action: title)
        }
        return "正在执行：\(action)"
    }

    private func localizedToolFailure(_ detail: String, action title: String) -> String {
        let safeDetail = redactDisplayText(detail)
        let lowered = safeDetail.lowercased()
        if lowered.contains("user cancelled") || lowered.contains("permission") || lowered.contains("授权") {
            return "未获得命令授权：\(localizedAction(title))"
        }
        if lowered.contains("network") || lowered.contains("connection") || lowered.contains("curl") || lowered.contains("网络") {
            return safeDetail.isEmpty
                ? "网络命令执行失败：\(localizedAction(title))"
                : "网络命令执行失败：\(safeDetail)"
        }
        return safeDetail.isEmpty
            ? "执行失败：\(localizedAction(title))"
            : "执行失败：\(localizedAction(title)) — \(safeDetail)"
    }

    private func localizedAction(_ title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("read") { return "读取" }
        if lowered.contains("edit") || lowered.contains("write") { return "编辑" }
        if lowered.contains("bash") || lowered.contains("command") || lowered.contains("terminal") { return "运行命令" }
        if lowered.contains("search") || lowered.contains("grep") { return "搜索" }
        if lowered.contains("test") { return "运行测试" }
        return title
    }

    private func redactDisplayText(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 180 { return cleaned }
        return String(cleaned.prefix(180)) + "…"
    }

    private func agentStage(for title: String) -> (name: String, color: NSColor) {
        let lowered = title.lowercased()
        if lowered.contains("test") || lowered.contains("check") {
            return ("Testing", Palette.success)
        }
        if lowered.contains("bash") || lowered.contains("command") || lowered.contains("terminal") {
            return ("Running", Palette.blue)
        }
        if lowered.contains("read") || lowered.contains("search") || lowered.contains("grep") {
            return ("Reviewing", Palette.violet)
        }
        if lowered.contains("edit") || lowered.contains("write") || lowered.contains("patch") {
            return ("Editing", Palette.accent)
        }
        return ("Thinking", Palette.accent)
    }
}

// MARK: - 应用入口

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let defaultWindowWidth: CGFloat = 1440
    static let defaultWindowHeight: CGFloat = 900
    static let minimumWindowWidth: CGFloat = 1180
    static let minimumWindowHeight: CGFloat = 720
    private static let windowFrameStorageKey = "ai-dev-one.window-frame"

    private var window: NSWindow?
    private var mainController: MainViewController?
    private var preferredWindowSize = NSSize(
        width: AppDelegate.defaultWindowWidth,
        height: AppDelegate.defaultWindowHeight
    )
    private var enforcingWindowBounds = false
    private var userIsResizingWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 升级自早期版本时，将 TOML 中的旧明文密钥迁移到 macOS 钥匙串。
        NexusConfiguration.shared.hardenPermissions()
        NexusConfiguration.shared.migrateLegacyAPIKeyIfNeeded()
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = makeApplicationIcon()

        let controller = MainViewController()
        controller.preferredContentSize = NSSize(
            width: Self.defaultWindowWidth,
            height: Self.defaultWindowHeight
        )
        let restoredFrame = validatedSavedWindowFrame()
        let initialWindowFrame = restoredFrame ?? defaultCenteredWindowFrame()
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.defaultWindowWidth,
                height: Self.defaultWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Dev One · Route 2"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.forestBottom
        // Work Monitor 可以在主窗口关闭后重新打开它。保持 NSWindow 对象
        // 有效，避免 AppKit 默认 releasedWhenClosed 导致 reopen 路径悬空。
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        let minimumSize = NSSize(width: Self.minimumWindowWidth, height: Self.minimumWindowHeight)
        window.minSize = minimumSize
        window.contentMinSize = minimumSize
        // 保留系统原生 contentView 作为 NSWindow 尺寸边界。隔离宿主只作为
        // frame/autoresize 子视图存在，三栏 fittingSize 无法再传播到窗口。
        let contentContainer: NSView
        if let existingContentView = window.contentView {
            contentContainer = existingContentView
        } else {
            let fallbackContentView = NSView(frame: NSRect(origin: .zero, size: initialWindowFrame.size))
            window.contentView = fallbackContentView
            contentContainer = fallbackContentView
        }
        let host = WindowContentHostView(
            hostedView: controller.view,
            frameSize: contentContainer.bounds.size
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        host.frame = contentContainer.bounds
        contentContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            host.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            host.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        preferredWindowSize = initialWindowFrame.size
        self.window = window
        mainController = controller
        controller.onRequestWindowSize = { [weak self] size in
            self?.updatePreferredWindowSize(size)
        }
        controller.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        if restoredFrame == nil {
            UserDefaults.standard.removeObject(forKey: Self.windowFrameStorageKey)
        }
        window.setFrame(initialWindowFrame, display: false)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        controller.prepareForDisplay()
        SecureCredentialStore.warmup { [weak controller] in
            controller?.refreshModelState()
        }
        installMainMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // 首轮窗口/Renderer 布局稳定后重新应用已验证的目标边界，确保默认
            // 1440×900 和用户保存的合法尺寸都能被准确恢复。
            self?.window?.setFrame(initialWindowFrame, display: true)
            self?.enforceWindowBounds()
            self?.saveWindowFrameIfValid()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(mainController?.isWorkMonitorVisible ?? false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q 不一定经过 windowShouldClose；这里也显式中断当前代理，
        // 避免退出桌面端后留下孤儿的 nexus-agent 子进程。
        mainController?.shutdownCore()
        return .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 关闭主窗口不是 Cmd+Q。若 Work Monitor 仍打开，应用继续运行，
        // 当前任务/Core 也继续运行；真正退出时由 applicationShouldTerminate
        // 统一执行 shutdownCore()。
        return true
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrameIfValid()
    }

    func windowDidResize(_ notification: Notification) {
        if let window,
           window.frame.width < Self.minimumWindowWidth || window.frame.height < Self.minimumWindowHeight {
            // 不在 AppKit 的约束布局回调内同步 setFrame，避免重入 display cycle。
            DispatchQueue.main.async { [weak self] in
                self?.enforceWindowBounds()
            }
            return
        }
        saveWindowFrameIfValid()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let safeSize = NSSize(
            width: max(frameSize.width, Self.minimumWindowWidth),
            height: max(frameSize.height, Self.minimumWindowHeight)
        )
        let isPointerResize = sender.inLiveResize && (NSEvent.pressedMouseButtons & 1) == 1
        if isPointerResize {
            userIsResizingWindow = true
            updatePreferredWindowSize(safeSize)
            return safeSize
        }
        // AppKit calls this delegate while toggling the standard zoom frame.
        // During the return trip `isZoomed` is still true, so returning the
        // previously stored (maximized) preferred size would reject the
        // restore operation.  Keep the minimum-size guard, but accept the
        // valid restore frame instead of feeding the zoomed size back.
        if sender.isZoomed {
            updatePreferredWindowSize(safeSize)
            return safeSize
        }
        // 约束引擎自身也会走到这里。非鼠标拖动时不接受它提出的
        // fittingSize（历史故障值为 28px / 1180px），继续保持显式目标尺寸。
        return preferredWindowSize
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard userIsResizingWindow else { return }
        userIsResizingWindow = false
        guard let window else { return }
        updatePreferredWindowSize(window.frame.size)
        saveWindowFrameIfValid()
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        updatePreferredWindowSize(newFrame.size)
        return newFrame
    }

    @objc private func resetLayout() {
        mainController?.resetLayout()
    }

    private func enforceWindowBounds() {
        guard !enforcingWindowBounds, let window else { return }
        var frame = window.frame
        let preferredSize = preferredWindowSize
        var changed = false
        if frame.width < Self.minimumWindowWidth {
            frame.size.width = max(Self.minimumWindowWidth, preferredSize.width)
            changed = true
        }
        if frame.height < Self.minimumWindowHeight {
            frame.size.height = max(Self.minimumWindowHeight, preferredSize.height)
            changed = true
        }
        guard changed else { return }
        enforcingWindowBounds = true
        defer { enforcingWindowBounds = false }
        updatePreferredWindowSize(frame.size)
        window.setFrame(frame, display: true)
    }

    private func updatePreferredWindowSize(_ size: NSSize) {
        let safeSize = NSSize(
            width: max(size.width, Self.minimumWindowWidth),
            height: max(size.height, Self.minimumWindowHeight)
        )
        preferredWindowSize = safeSize
    }

    private func showMainWindow() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func saveWindowFrameIfValid() {
        guard let window, isValidWindowFrame(window.frame) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.windowFrameStorageKey)
    }

    private func validatedSavedWindowFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: Self.windowFrameStorageKey),
              !raw.isEmpty else { return nil }
        let frame = NSRectFromString(raw)
        guard isValidWindowFrame(frame) else {
            UserDefaults.standard.removeObject(forKey: Self.windowFrameStorageKey)
            return nil
        }
        return frame
    }

    private func defaultCenteredWindowFrame() -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(
                x: 0,
                y: 0,
                width: Self.defaultWindowWidth,
                height: Self.defaultWindowHeight
            )
        return NSRect(
            x: screenFrame.midX - Self.defaultWindowWidth / 2,
            y: screenFrame.midY - Self.defaultWindowHeight / 2,
            width: Self.defaultWindowWidth,
            height: Self.defaultWindowHeight
        )
    }

    private func isValidWindowFrame(_ frame: NSRect) -> Bool {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width >= Self.minimumWindowWidth,
              frame.height >= Self.minimumWindowHeight else {
            return false
        }

        let screens = NSScreen.screens
        let maximumScreenWidth = screens.map { $0.frame.width }.max() ?? 0
        let maximumScreenHeight = screens.map { $0.frame.height }.max() ?? 0
        guard !screens.isEmpty,
              frame.width <= maximumScreenWidth,
              frame.height <= maximumScreenHeight else {
            return false
        }
        return screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Nexus", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let resetItem = NSMenuItem(title: "重置界面布局", action: #selector(resetLayout), keyEquivalent: "0")
        resetItem.keyEquivalentModifierMask = [.command, .shift]
        resetItem.target = self
        appMenu.addItem(resetItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Nexus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        let monitorItem = NSMenuItem(title: "工作监控", action: #selector(MainViewController.showWorkMonitorFromMenu), keyEquivalent: "")
        monitorItem.target = mainController
        windowMenu.addItem(monitorItem)
        NSApp.windowsMenu = windowMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    private func makeApplicationIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        let outer = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 456, height: 456), xRadius: 112, yRadius: 112)
        NSColor(calibratedRed: 0.025, green: 0.28, blue: 0.30, alpha: 1).setFill()
        outer.fill()
        let inner = NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 422, height: 422), xRadius: 102, yRadius: 102)
        NSColor(calibratedRed: 0.06, green: 0.58, blue: 0.56, alpha: 1).setFill()
        inner.fill()
        let text = "N"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 270, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 - 7),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
