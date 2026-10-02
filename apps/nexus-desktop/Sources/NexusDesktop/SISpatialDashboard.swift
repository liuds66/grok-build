import AppKit
import Foundation

// MARK: - SIBrain Nexus Spatial SI OS

/// Product-facing navigation for the Spatial SI shell.  These values are
/// presentation routes only; existing chat, workspace, task, and settings
/// handlers remain the source of truth for the underlying operations.
enum SISpatialSection: String, CaseIterable {
    case overview = "总览"
    case conversation = "对话"
    case agents = "智能体"
    case workflows = "工作流"
    case tasks = "任务"
    case devices = "设备"
    case knowledge = "知识库"
    case files = "文件"
    case models = "模型中心"
    case observability = "可观测性"
    case security = "安全"
    case plugins = "插件 / MCP"
    case developer = "开发者中心"
    case settings = "设置"
}

private final class SIActionButton: NSButton {
    var onTap: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var normalFill = NSColor.white.withAlphaComponent(0.09)
    private var hoverFill = NSColor.white.withAlphaComponent(0.19)

    init(title: String = "", icon: String? = nil, fontSize: CGFloat = 12) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .texturedRounded
        self.title = title
        font = .systemFont(ofSize: fontSize, weight: .medium)
        alignment = .left
        imagePosition = icon == nil ? .noImage : .imageLeading
        image = icon.flatMap { symbol($0, size: 15, weight: .medium) }
        contentTintColor = NSColor(calibratedWhite: 0.98, alpha: 0.92)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = normalFill.cgColor
        target = self
        action = #selector(trigger)
        setAccessibilityLabel(title)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hoverFill.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = normalFill.cgColor }

    @objc private func trigger() { onTap?() }
}

private final class SISpatialBackdropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        let colors = [
            NSColor(calibratedRed: 0.055, green: 0.18, blue: 0.44, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.055, green: 0.42, blue: 0.72, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.48, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.17, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.68, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.width * 0.08, y: rect.height),
                end: CGPoint(x: rect.width * 0.92, y: 0),
                options: []
            )
        }

        context.saveGState()
        drawGlow(context: context, center: CGPoint(x: rect.width * 0.50, y: rect.height * 0.52), radius: min(rect.width, rect.height) * 0.34, color: Palette.blue, alpha: 0.30)
        drawGlow(context: context, center: CGPoint(x: rect.width * 0.86, y: rect.height * 0.82), radius: min(rect.width, rect.height) * 0.24, color: Palette.violet, alpha: 0.20)
        drawGlow(context: context, center: CGPoint(x: rect.width * 0.12, y: rect.height * 0.18), radius: min(rect.width, rect.height) * 0.22, color: Palette.accent, alpha: 0.16)

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.045).cgColor)
        context.setLineWidth(0.6)
        let step: CGFloat = 64
        stride(from: -rect.height, through: rect.width + rect.height, by: step).forEach { offset in
            context.move(to: CGPoint(x: offset, y: 0))
            context.addLine(to: CGPoint(x: offset + rect.height, y: rect.height))
        }
        context.strokePath()

        context.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        var seed: UInt32 = 117
        for _ in 0..<100 {
            seed = 1664525 &* seed &+ 1013904223
            let x = CGFloat(seed % 1000) / 1000 * rect.width
            seed = 1664525 &* seed &+ 1013904223
            let y = CGFloat(seed % 1000) / 1000 * rect.height
            let radius = CGFloat(seed % 3 + 1) * 0.38
            context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
        context.restoreGState()
    }

    private func drawGlow(context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
        for step in stride(from: 1.0, through: 0.10, by: -0.08) {
            let current = radius * step
            context.setFillColor(color.withAlphaComponent(alpha * (1 - step) * 0.34).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - current, y: center.y - current, width: current * 2, height: current * 2))
        }
    }
}

private final class SICoreOrbView: NSView {
    var stateText: String = "就绪 · 等待任务" { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("SI Core")
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let side = min(bounds.width, bounds.height) * 0.64
        let sphere = CGRect(x: (bounds.width - side) / 2, y: bounds.midY - side * 0.43, width: side, height: side)
        let center = CGPoint(x: sphere.midX, y: sphere.midY)
        let radius = side / 2

        for index in stride(from: 12, through: 1, by: -1) {
            let glow = radius + CGFloat(index) * 9
            context.setFillColor(NSColor(calibratedRed: 0.24, green: 0.76, blue: 1, alpha: 0.010 + CGFloat(13 - index) * 0.003).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2))
        }

        let sphereColors = [
            NSColor(calibratedRed: 0.38, green: 0.93, blue: 1, alpha: 0.86).cgColor,
            NSColor(calibratedRed: 0.19, green: 0.50, blue: 1, alpha: 0.95).cgColor,
            NSColor(calibratedRed: 0.31, green: 0.17, blue: 0.92, alpha: 0.95).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sphereColors, locations: [0, 0.52, 1]) {
            context.saveGState()
            context.addEllipse(in: sphere)
            context.clip()
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: sphere.minX + side * 0.28, y: sphere.maxY - side * 0.24), startRadius: 0, endCenter: center, endRadius: radius * 1.25, options: [])
            context.restoreGState()
        }

        context.saveGState()
        context.addEllipse(in: sphere.insetBy(dx: 1, dy: 1))
        context.clip()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.26).cgColor)
        context.setLineWidth(1.2)
        for index in 0..<7 {
            let y = sphere.minY + CGFloat(index + 1) / 8 * sphere.height
            context.move(to: CGPoint(x: sphere.minX - 12, y: y + sin(CGFloat(index)) * 8))
            context.addCurve(to: CGPoint(x: sphere.maxX + 12, y: y), control1: CGPoint(x: sphere.width * 0.28, y: y + 28), control2: CGPoint(x: sphere.width * 0.74, y: y - 26))
        }
        for index in 0..<6 {
            let x = sphere.minX + CGFloat(index + 1) / 7 * sphere.width
            context.move(to: CGPoint(x: x, y: sphere.minY - 12))
            context.addCurve(to: CGPoint(x: x + 10, y: sphere.maxY + 12), control1: CGPoint(x: x - 30, y: sphere.height * 0.28), control2: CGPoint(x: x + 30, y: sphere.height * 0.72))
        }
        context.strokePath()
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: sphere.insetBy(dx: 1, dy: 1))
        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        for index in 0..<6 {
            let phase = CGFloat(index) * 0.93
            let point = CGPoint(x: center.x + cos(phase) * radius * 0.56, y: center.y + sin(phase) * radius * 0.56)
            context.fillEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        }

        let title = "SI Core" as NSString
        title.draw(at: CGPoint(x: center.x - 37, y: center.y - 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let state = stateText as NSString
        state.draw(at: CGPoint(x: center.x - min(86, CGFloat(state.length) * 3.8), y: sphere.minY - 32), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
        ])
    }
}

private final class SICognitiveOrbitView: NSView {
    var onSelect: ((SISpatialSection) -> Void)?
    private let orb = SICoreOrbView()
    private var nodes: [(button: SIActionButton, section: SISpatialSection)] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(orb)
        let specs: [(String, String, SISpatialSection)] = [
            ("理解", "分析意图", .conversation),
            ("规划", "制定方案", .agents),
            ("执行", "调用工具", .workflows),
            ("验证", "检查结果", .tasks),
            ("进化", "持续学习", .models),
        ]
        nodes = specs.map { title, subtitle, section in
            let buttonTitle = title + "  ·  " + subtitle
            let button = SIActionButton(title: buttonTitle, icon: "sparkles", fontSize: 12)
            button.alignment = .center
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = "打开\(title) · \(subtitle)"
            button.onTap = { [weak self] in self?.onSelect?(section) }
            addSubview(button)
            return (button, section)
        }
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    func update(state: String) { orb.stateText = state }

    override func layout() {
        super.layout()
        let orbSize = min(250, max(178, min(bounds.width, bounds.height) * 0.54))
        orb.frame = NSRect(x: bounds.midX - orbSize / 2, y: bounds.midY - orbSize / 2 + 8, width: orbSize, height: orbSize)
        let positions: [(CGFloat, CGFloat)] = [
            (0.07, 0.62), (0.40, 0.87), (0.74, 0.65), (0.71, 0.10), (0.26, 0.12),
        ]
        let nodeWidth = min(134, max(106, bounds.width * 0.17))
        let nodeHeight: CGFloat = 54
        for (index, node) in nodes.enumerated() where index < positions.count {
            let (x, y) = positions[index]
            node.button.frame = NSRect(x: bounds.width * x - nodeWidth * 0.16, y: bounds.height * y - nodeHeight / 2, width: nodeWidth, height: nodeHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY + 8)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 7])
        for radius in [bounds.height * 0.22, bounds.height * 0.38, bounds.height * 0.52] {
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.66, width: radius * 2, height: radius * 1.32))
        }
        context.setLineDash(phase: 0, lengths: [])
    }
}

final class SISpatialDashboardView: LayerView {
    var onSectionSelected: ((SISpatialSection) -> Void)?

    private let commandField = NSTextField()
    private let statePill = NSTextField(labelWithString: "就绪")
    private let coreState = NSTextField(labelWithString: "就绪 · 等待任务")
    private let taskTitle = NSTextField(labelWithString: "暂无运行任务")
    private let taskDetail = NSTextField(labelWithString: "提交任务后，这里会显示真实执行摘要")
    private let runtimeValue = NSTextField(labelWithString: "Ready")
    private let modelValue = NSTextField(labelWithString: "未配置")
    private let agentValue = NSTextField(labelWithString: "Agent 空闲")
    private let agentsContent = NSTextField(labelWithString: "暂无运行中的智能体")
    private let workflowContent = NSTextField(labelWithString: "暂无运行中的工作流")
    private let deviceContent = NSTextField(labelWithString: "未读取设备遥测")
    private let recentContent = NSTextField(labelWithString: "暂无可展示的运行活动")
    private let orbit = SICognitiveOrbitView()
    private var summary = WorkActivitySummary.idle

    init() {
        super.init(fillColor: .clear, cornerRadius: 0)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        buildInterface()
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }

    func update(summary: WorkActivitySummary) {
        self.summary = summary
        let state = summary.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "就绪 · 等待任务" : summary.status
        coreState.stringValue = state == "空闲" ? "就绪 · 等待任务" : state
        orbit.update(state: coreState.stringValue)
        statePill.stringValue = state == "空闲" ? "●  就绪" : "●  " + state
        let activeColor = state == "空闲" ? Palette.accent : Palette.success
        statePill.textColor = activeColor
        statePill.layer?.backgroundColor = activeColor.withAlphaComponent(0.14).cgColor
        statePill.layer?.borderColor = activeColor.withAlphaComponent(0.35).cgColor
        taskTitle.stringValue = summary.taskID.isEmpty ? "暂无运行任务" : compact(summary.taskTitle, limit: 54)
        taskDetail.stringValue = summary.taskID.isEmpty ? "提交任务后，这里会显示真实执行摘要" : compact(summary.activity, limit: 86)
        runtimeValue.stringValue = compact(summary.coreStatus, limit: 24)
        modelValue.stringValue = compact(summary.modelStatus, limit: 24)
        agentValue.stringValue = compact(summary.agentStatus, limit: 24)
        agentsContent.stringValue = runningStageText(summary)
        workflowContent.stringValue = summary.taskID.isEmpty ? "暂无运行中的工作流" : compact(summary.activity, limit: 90)
        deviceContent.stringValue = "当前产品未提供设备遥测"
        recentContent.stringValue = recentText(summary)
        [runtimeValue, modelValue, agentValue].forEach { $0.textColor = NSColor.white.withAlphaComponent(0.86) }
    }

    private func buildInterface() {
        let atmosphere = SISpatialBackdropView()
        atmosphere.translatesAutoresizingMaskIntoConstraints = false
        addSubview(atmosphere)
        atmosphere.pinEdges(to: self)

        let dock = makeDock()
        addSubview(dock)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            dock.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            dock.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            // Bind both edges to the shell.  The explicit trailing anchor
            // keeps the dock stable when AppKit resolves the glass subview
            // hierarchy during the first window layout pass.
            dock.trailingAnchor.constraint(equalTo: leadingAnchor, constant: 208),
        ])

        let commandBar = makeCommandBar()
        addSubview(commandBar)
        NSLayoutConstraint.activate([
            commandBar.leadingAnchor.constraint(equalTo: dock.trailingAnchor, constant: 20),
            commandBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            commandBar.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            commandBar.heightAnchor.constraint(equalToConstant: 48),
        ])

        let hero = makeHero()
        let context = makeContextPanel()
        let topRow = NSStackView(views: [hero, context])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.orientation = .horizontal
        topRow.spacing = 14
        topRow.alignment = .top
        topRow.distribution = .fill
        addSubview(topRow)

        let quick = makeQuickActions()
        addSubview(quick)
        let lower = makeLowerPanels()
        addSubview(lower)

        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: commandBar.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: commandBar.trailingAnchor),
            topRow.topAnchor.constraint(equalTo: commandBar.bottomAnchor, constant: 14),
            topRow.heightAnchor.constraint(equalToConstant: 306),
            hero.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            context.widthAnchor.constraint(equalToConstant: 302),
            quick.leadingAnchor.constraint(equalTo: commandBar.leadingAnchor),
            quick.trailingAnchor.constraint(equalTo: commandBar.trailingAnchor),
            quick.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 12),
            quick.heightAnchor.constraint(equalToConstant: 66),
            lower.leadingAnchor.constraint(equalTo: commandBar.leadingAnchor),
            lower.trailingAnchor.constraint(equalTo: commandBar.trailingAnchor),
            lower.topAnchor.constraint(equalTo: quick.bottomAnchor, constant: 12),
            lower.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            lower.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])

        update(summary: .idle)
    }

    private func makeDock() -> NSView {
        let dock = LayerView(fillColor: NSColor.white.withAlphaComponent(0.12), cornerRadius: 24, strokeColor: NSColor.white.withAlphaComponent(0.22))
        dock.translatesAutoresizingMaskIntoConstraints = false

        let brand = label("SIBrain Nexus", size: 16, weight: .semibold, color: .white)
        let subtitle = label("Spatial SI OS", size: 10.5, color: NSColor.white.withAlphaComponent(0.68))
        brand.maximumNumberOfLines = 1
        brand.lineBreakMode = .byClipping
        let brandStack = NSStackView(views: [brand, subtitle])
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        brandStack.orientation = .vertical
        brandStack.spacing = 2
        let logo = LayerView(fillColor: NSColor.white.withAlphaComponent(0.20), cornerRadius: 17, strokeColor: NSColor.white.withAlphaComponent(0.38))
        logo.translatesAutoresizingMaskIntoConstraints = false
        let logoIcon = NSImageView()
        logoIcon.translatesAutoresizingMaskIntoConstraints = false
        logoIcon.image = symbol("circle.hexagongrid.fill", size: 18, weight: .medium)
        logoIcon.contentTintColor = .white
        logo.addSubview(logoIcon)
        logoIcon.pinEdges(to: logo, insets: NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7))

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(logo)
        header.addSubview(brandStack)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 34),
            logo.heightAnchor.constraint(equalToConstant: 34),
            brandStack.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 10),
            brandStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            brandStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])

        let primary = SISpatialSection.allCases
        let navStack = NSStackView()
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navStack.orientation = .vertical
        navStack.spacing = 3
        navStack.alignment = .width
        for section in primary {
            let button = SIActionButton(title: section.rawValue, icon: iconName(for: section), fontSize: 12.5)
            button.onTap = { [weak self] in self?.onSectionSelected?(section) }
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            navStack.addArrangedSubview(button)
        }

        let footer = SIActionButton(title: "本地工作区", icon: "person.crop.circle", fontSize: 11.5)
        footer.toolTip = "当前运行在本机；不会伪造外部设备或发布状态"
        footer.onTap = { [weak self] in self?.onSectionSelected?(.settings) }
        footer.heightAnchor.constraint(equalToConstant: 36).isActive = true
        footer.contentTintColor = NSColor.white.withAlphaComponent(0.78)

        [header, navStack, footer].forEach(dock.addSubview)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: dock.topAnchor, constant: 16),
            header.heightAnchor.constraint(equalToConstant: 42),
            navStack.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 10),
            navStack.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -10),
            navStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 19),
            navStack.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: dock.bottomAnchor, constant: -14),
        ])
        return dock
    }

    private func makeCommandBar() -> NSView {
        let bar = LayerView(fillColor: NSColor.white.withAlphaComponent(0.14), cornerRadius: 23, strokeColor: NSColor.white.withAlphaComponent(0.30))
        bar.translatesAutoresizingMaskIntoConstraints = false

        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.placeholderString = "搜索、提问或下达指令…"
        commandField.font = .systemFont(ofSize: 13, weight: .regular)
        commandField.textColor = .white
        commandField.placeholderAttributedString = NSAttributedString(string: "搜索、提问或下达指令…", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.58)])
        commandField.isBordered = false
        commandField.drawsBackground = false
        commandField.focusRingType = .none
        commandField.target = self
        commandField.action = #selector(commandSubmitted)
        commandField.setAccessibilityLabel("搜索、提问或下达指令")

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = symbol("magnifyingglass", size: 16, weight: .medium)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        let shortcut = label("⌘ K", size: 11, color: NSColor.white.withAlphaComponent(0.55))
        shortcut.alignment = .center
        shortcut.wantsLayer = true
        shortcut.layer?.cornerRadius = 8
        shortcut.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let voice = SIActionButton(title: "", icon: "mic.fill", fontSize: 11)
        voice.imagePosition = .imageOnly
        voice.toolTip = "语音输入由现有运行时提供时可用"
        voice.onTap = { [weak self] in self?.onSectionSelected?(.conversation) }
        voice.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let notification = SIActionButton(title: "", icon: "bell", fontSize: 11)
        notification.imagePosition = .imageOnly
        notification.toolTip = "通知"
        notification.onTap = { [weak self] in self?.onSectionSelected?(.tasks) }
        notification.widthAnchor.constraint(equalToConstant: 34).isActive = true
        [icon, commandField, shortcut, voice, notification].forEach(bar.addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            commandField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            commandField.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            commandField.trailingAnchor.constraint(equalTo: shortcut.leadingAnchor, constant: -10),
            shortcut.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            shortcut.widthAnchor.constraint(equalToConstant: 42),
            shortcut.heightAnchor.constraint(equalToConstant: 22),
            voice.leadingAnchor.constraint(equalTo: shortcut.trailingAnchor, constant: 14),
            voice.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            voice.heightAnchor.constraint(equalToConstant: 32),
            notification.leadingAnchor.constraint(equalTo: voice.trailingAnchor, constant: 6),
            notification.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            notification.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            notification.heightAnchor.constraint(equalToConstant: 32),
        ])
        return bar
    }

    private func makeHero() -> NSView {
        let hero = LayerView(fillColor: NSColor.white.withAlphaComponent(0.10), cornerRadius: 26, strokeColor: NSColor.white.withAlphaComponent(0.23))
        hero.translatesAutoresizingMaskIntoConstraints = false
        let heading = label("SI Command Center", size: 13, weight: .medium, color: NSColor.white.withAlphaComponent(0.82))
        heading.translatesAutoresizingMaskIntoConstraints = false
        let hint = label("空间智能工作台 · 真实运行时状态", size: 11, color: NSColor.white.withAlphaComponent(0.56))
        hint.translatesAutoresizingMaskIntoConstraints = false
        orbit.translatesAutoresizingMaskIntoConstraints = false
        [heading, hint, orbit].forEach(hero.addSubview)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 22),
            heading.topAnchor.constraint(equalTo: hero.topAnchor, constant: 17),
            hint.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 10),
            hint.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            orbit.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 6),
            orbit.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -6),
            orbit.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 1),
            orbit.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -2),
        ])
        return hero
    }

    private func makeContextPanel() -> NSView {
        let panel = LayerView(fillColor: NSColor.white.withAlphaComponent(0.14), cornerRadius: 24, strokeColor: NSColor.white.withAlphaComponent(0.28))
        panel.translatesAutoresizingMaskIntoConstraints = false
        let title = label("SI Core 当前状态", size: 16, weight: .semibold, color: .white)
        title.translatesAutoresizingMaskIntoConstraints = false
        statePill.translatesAutoresizingMaskIntoConstraints = false
        statePill.alignment = .center
        statePill.font = .systemFont(ofSize: 10.5, weight: .semibold)
        statePill.wantsLayer = true
        statePill.layer?.cornerRadius = 10
        statePill.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.14).cgColor
        statePill.layer?.borderWidth = 1
        statePill.layer?.borderColor = Palette.accent.withAlphaComponent(0.35).cgColor

        let currentLabel = label("当前任务", size: 11, weight: .medium, color: NSColor.white.withAlphaComponent(0.68))
        currentLabel.translatesAutoresizingMaskIntoConstraints = false
        taskTitle.translatesAutoresizingMaskIntoConstraints = false
        taskTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        taskTitle.textColor = .white
        taskDetail.translatesAutoresizingMaskIntoConstraints = false
        taskDetail.font = .systemFont(ofSize: 11)
        taskDetail.textColor = NSColor.white.withAlphaComponent(0.60)
        taskDetail.lineBreakMode = .byTruncatingTail
        let taskCard = LayerView(fillColor: NSColor.white.withAlphaComponent(0.10), cornerRadius: 16, strokeColor: NSColor.white.withAlphaComponent(0.16))
        taskCard.translatesAutoresizingMaskIntoConstraints = false
        [taskTitle, taskDetail].forEach(taskCard.addSubview)

        let metrics = NSStackView(views: [metric("智能体", agentValue), metric("运行时", runtimeValue), metric("模型", modelValue)])
        metrics.translatesAutoresizingMaskIntoConstraints = false
        metrics.orientation = .horizontal
        metrics.distribution = .fillEqually
        metrics.spacing = 1

        [title, statePill, currentLabel, taskCard, metrics].forEach(panel.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            statePill.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            statePill.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            statePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            statePill.heightAnchor.constraint(equalToConstant: 22),
            currentLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            currentLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            taskCard.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            taskCard.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            taskCard.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 9),
            taskCard.heightAnchor.constraint(equalToConstant: 66),
            taskTitle.leadingAnchor.constraint(equalTo: taskCard.leadingAnchor, constant: 14),
            taskTitle.trailingAnchor.constraint(equalTo: taskCard.trailingAnchor, constant: -12),
            taskTitle.topAnchor.constraint(equalTo: taskCard.topAnchor, constant: 14),
            taskDetail.leadingAnchor.constraint(equalTo: taskTitle.leadingAnchor),
            taskDetail.trailingAnchor.constraint(equalTo: taskTitle.trailingAnchor),
            taskDetail.topAnchor.constraint(equalTo: taskTitle.bottomAnchor, constant: 6),
            metrics.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            metrics.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            metrics.topAnchor.constraint(equalTo: taskCard.bottomAnchor, constant: 14),
            metrics.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -18),
            metrics.heightAnchor.constraint(equalToConstant: 46),
        ])
        return panel
    }

    private func metric(_ title: String, _ value: NSTextField) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = value
        valueLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.lineBreakMode = .byTruncatingTail
        let titleLabel = label(title, size: 10, color: NSColor.white.withAlphaComponent(0.58))
        titleLabel.alignment = .center
        [valueLabel, titleLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: card.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 3),
        ])
        return card
    }

    private func makeQuickActions() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        let items: [(String, String, SISpatialSection)] = [
            ("对话", "bubble.left.and.bubble.right.fill", .conversation),
            ("智能体", "person.3.fill", .agents),
            ("工作流", "point.3.connected.trianglepath.dotted", .workflows),
            ("知识库", "books.vertical.fill", .knowledge),
            ("文件", "folder.fill", .files),
            ("设备", "desktopcomputer", .devices),
        ]
        for (title, icon, section) in items {
            let button = SIActionButton(title: title, icon: icon, fontSize: 12)
            button.imagePosition = .imageAbove
            button.alignment = .center
            button.onTap = { [weak self] in self?.onSectionSelected?(section) }
            button.heightAnchor.constraint(equalToConstant: 66).isActive = true
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private func makeLowerPanels() -> NSView {
        let panels: [(String, String, NSTextField)] = [
            ("智能体运行", "person.3.fill", agentsContent),
            ("工作流执行", "arrow.triangle.branch", workflowContent),
            ("设备状态", "desktopcomputer", deviceContent),
            ("最近任务", "clock.arrow.circlepath", recentContent),
        ]
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        for (title, icon, content) in panels {
            let panel = LayerView(fillColor: NSColor.white.withAlphaComponent(0.12), cornerRadius: 20, strokeColor: NSColor.white.withAlphaComponent(0.21))
            panel.translatesAutoresizingMaskIntoConstraints = false
            let headingIcon = NSImageView()
            headingIcon.translatesAutoresizingMaskIntoConstraints = false
            headingIcon.image = symbol(icon, size: 13, weight: .medium)
            headingIcon.contentTintColor = NSColor.white.withAlphaComponent(0.88)
            headingIcon.widthAnchor.constraint(equalToConstant: 15).isActive = true
            headingIcon.heightAnchor.constraint(equalToConstant: 15).isActive = true
            let headingLabel = label(title, size: 12.5, weight: .semibold, color: .white)
            let heading = NSStackView(views: [headingIcon, headingLabel])
            heading.translatesAutoresizingMaskIntoConstraints = false
            heading.orientation = .horizontal
            heading.spacing = 6
            heading.alignment = .centerY
            content.translatesAutoresizingMaskIntoConstraints = false
            content.font = .systemFont(ofSize: 11.5, weight: .regular)
            content.textColor = NSColor.white.withAlphaComponent(0.66)
            content.maximumNumberOfLines = 3
            content.lineBreakMode = .byTruncatingTail
            [heading, content].forEach(panel.addSubview)
            NSLayoutConstraint.activate([
                heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 15),
                heading.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
                heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 15),
                content.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
                content.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
                content.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -15),
            ])
            stack.addArrangedSubview(panel)
        }
        return stack
    }

    @objc private func commandSubmitted() {
        let query = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        commandField.stringValue = ""
        let route: SISpatialSection?
        if query.contains("对话") || query.contains("chat") { route = .conversation }
        else if query.contains("智能体") || query.contains("agent") { route = .agents }
        else if query.contains("工作流") || query.contains("workflow") { route = .workflows }
        else if query.contains("任务") || query.contains("task") { route = .tasks }
        else if query.contains("知识") || query.contains("knowledge") { route = .knowledge }
        else if query.contains("文件") || query.contains("file") { route = .files }
        else if query.contains("设置") || query.contains("setting") { route = .settings }
        else { route = query.isEmpty ? nil : .overview }
        if let route { onSectionSelected?(route) }
    }

    private func runningStageText(_ summary: WorkActivitySummary) -> String {
        let active = summary.stages.filter { $0.state == .active }
        if !active.isEmpty { return active.map { "\($0.name) · \($0.detail)" }.joined(separator: "\n") }
        return summary.taskID.isEmpty ? "暂无运行中的智能体" : "当前没有可展示的智能体阶段"
    }

    private func recentText(_ summary: WorkActivitySummary) -> String {
        guard !summary.recentActivities.isEmpty else { return "暂无可展示的运行活动" }
        return summary.recentActivities.prefix(3).map { activity in
            let marker = activity.state == .failed ? "!" : activity.state == .active ? "•" : "✓"
            return "\(marker) \(compact(activity.title, limit: 38))"
        }.joined(separator: "\n")
    }

    private func compact(_ text: String, limit: Int) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
    }

    private func iconName(for section: SISpatialSection) -> String {
        switch section {
        case .overview: return "house.fill"
        case .conversation: return "bubble.left.and.bubble.right"
        case .agents: return "person.3"
        case .workflows: return "point.3.connected.trianglepath.dotted"
        case .tasks: return "checklist"
        case .devices: return "desktopcomputer"
        case .knowledge: return "books.vertical"
        case .files: return "doc.on.doc"
        case .models: return "cube.transparent"
        case .observability: return "waveform.path.ecg"
        case .security: return "lock.shield"
        case .plugins: return "puzzlepiece.extension"
        case .developer: return "hammer"
        case .settings: return "gearshape"
        }
    }
}
