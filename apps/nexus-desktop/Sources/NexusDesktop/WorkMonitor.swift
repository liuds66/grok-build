import AppKit
import Foundation

extension ModelState {
    var monitorLabel: String {
        switch self {
        case .ready: return "模型就绪"
        case .missingKey: return "模型配置异常"
        case .unauthorized: return "API Key 无效"
        case .rateLimited: return "请求受限"
        case .offline: return "接口离线"
        case .configurationError: return "模型配置异常"
        }
    }
}

// MARK: - Work Monitor 展示层模型

/// Work Monitor 只接收已经脱敏、面向用户的执行摘要。它不是 Agent/Core
/// 的第二套状态机，也不保存 prompt、工具原始参数或隐藏推理。
enum WorkMonitorItemState: String {
    case success
    case active
    case pending
    case warning
    case failed
}

struct WorkStageDisplay {
    let name: String
    let state: WorkMonitorItemState
    let detail: String
}

struct WorkRecentActivity {
    let state: WorkMonitorItemState
    let title: String
    let detail: String?
}

struct WorkVerificationItem {
    let name: String
    let state: WorkMonitorItemState
    let statusText: String
    let detail: String?
}

struct WorkFileActivity {
    let marker: String
    let name: String
    let path: String?
}

struct WorkGitHubSummary {
    let repository: String?
    let issue: String?
    let branch: String?
    let pullRequest: String?
    let ci: String?
    let state: WorkMonitorItemState
}

struct WorkActivitySummary {
    var taskTitle: String
    var projectName: String
    var projectPath: String
    var elapsedSince: Date?
    var status: String
    var currentStage: String
    var stages: [WorkStageDisplay]
    var actionType: String
    var target: String
    var targetPath: String?
    var purpose: String
    var activity: String
    var recentActivities: [WorkRecentActivity]
    var verificationItems: [WorkVerificationItem]
    var files: [WorkFileActivity]
    var coreStatus: String
    var modelStatus: String
    var agentStatus: String
    var github: WorkGitHubSummary?

    static var idle: WorkActivitySummary {
        WorkActivitySummary(
            taskTitle: "等待新的开发任务",
            projectName: "未选择项目",
            projectPath: "",
            elapsedSince: nil,
            status: "空闲",
            currentStage: "—",
            stages: WorkActivitySummary.defaultStages,
            actionType: "等待",
            target: "暂无活动",
            targetPath: nil,
            purpose: "提交任务后，这里会显示 AI 正在处理的对象和目的。",
            activity: "等待用户提交任务",
            recentActivities: [],
            verificationItems: WorkActivitySummary.defaultVerification,
            files: [],
            coreStatus: "Ready",
            modelStatus: "模型就绪",
            agentStatus: "Agent 空闲",
            github: nil
        )
    }

    static var defaultStages: [WorkStageDisplay] {
        [
            WorkStageDisplay(name: "Architect", state: .pending, detail: "等待"),
            WorkStageDisplay(name: "Builder", state: .pending, detail: "等待"),
            WorkStageDisplay(name: "Verifier", state: .pending, detail: "等待"),
            WorkStageDisplay(name: "Reviewer", state: .pending, detail: "等待"),
        ]
    }

    static var defaultVerification: [WorkVerificationItem] {
        [
            WorkVerificationItem(name: "相关测试", state: .pending, statusText: "等待", detail: nil),
            WorkVerificationItem(name: "Swift Typecheck", state: .pending, statusText: "等待", detail: nil),
            WorkVerificationItem(name: "Desktop Build", state: .pending, statusText: "等待", detail: nil),
            WorkVerificationItem(name: "Browser Verify", state: .pending, statusText: "未开始", detail: nil),
            WorkVerificationItem(name: "Reviewer", state: .pending, statusText: "等待", detail: nil),
        ]
    }
}

/// 所有进入 Work Monitor 的文本都经过这一层。文件路径由控制器先转成
/// 相对路径；这里再做凭据、绝对 home 路径和过长内容的最后一道保护。
enum WorkMonitorRedaction {
    static func text(_ value: String, limit: Int = 260) -> String {
        var result = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty { result = result.replacingOccurrences(of: home, with: "~") }

        let patterns: [(String, String)] = [
            (#"(?i)sk-[A-Za-z0-9_.*=+\-/]{8,}"#, "<redacted-key>"),
            (#"(?i)xai-[A-Za-z0-9_.*=+\-/]{8,}"#, "<redacted-key>"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+\-/=]+"#, "$1<redacted-key>"),
            (#"(?i)(api[_-]?key\s*[=:]\s*)[^\s,&]+"#, "$1<redacted-key>"),
            (#"(?i)(authorization\s*[=:]\s*)[^\s,&]+"#, "$1<redacted>"),
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
        // A raw thought/private-reasoning event must never become a monitor row.
        let lowered = result.lowercased()
        if lowered.contains("chain of thought") || lowered.contains("private reasoning") || lowered.contains("system prompt") {
            return "正在处理任务摘要"
        }
        return result.count > limit ? String(result.prefix(limit)) + "…" : result
    }
}

// MARK: - Work Monitor Window

final class WorkMonitorWindowController: NSWindowController {
    private let monitorView: WorkMonitorView
    private var didCenter = false

    init() {
        monitorView = WorkMonitorView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 860),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Dev One · 工作监控"
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 640, height: 700)
        window.isReleasedWhenClosed = false
        window.contentView = monitorView
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    func show(summary: WorkActivitySummary) {
        monitorView.update(summary: summary)
        if !didCenter {
            window?.center()
            didCenter = true
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(summary: WorkActivitySummary) {
        monitorView.update(summary: summary)
    }
}

final class WorkMonitorView: LayerView {
    private let scrollView = NSScrollView()
    private let documentView = LayerView(fillColor: .clear)
    private let bodyStack = NSStackView()
    private let headerStatus = label("● Agent 空闲", size: 11, weight: .medium, color: Palette.secondaryText)
    private var elapsedLabel: NSTextField?
    private var currentSummary = WorkActivitySummary.idle
    private var timer: Timer?

    override init(fillColor: NSColor = Palette.canvas, cornerRadius: CGFloat = 0, strokeColor: NSColor? = nil) {
        super.init(fillColor: fillColor, cornerRadius: cornerRadius, strokeColor: strokeColor)
        translatesAutoresizingMaskIntoConstraints = false
        buildView()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshElapsed()
        }
    }

    convenience init() {
        self.init(fillColor: Palette.canvas, cornerRadius: 0, strokeColor: Palette.border.withAlphaComponent(0.6))
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    deinit {
        timer?.invalidate()
    }

    func update(summary: WorkActivitySummary) {
        currentSummary = summary
        render()
    }

    private func buildView() {
        let backdrop = ForestBackdropView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let header = LayerView(fillColor: Palette.sidebar.withAlphaComponent(0.72), cornerRadius: 0, strokeColor: Palette.border)
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = label("AI Dev One · 工作监控", size: 16, weight: .semibold, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        title.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = label("安全执行摘要 · 不显示隐藏推理或敏感参数", size: 10.5, color: Palette.secondaryText)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        headerStatus.translatesAutoresizingMaskIntoConstraints = false
        headerStatus.alignment = .center
        headerStatus.wantsLayer = true
        headerStatus.layer?.cornerRadius = 11
        headerStatus.layer?.borderWidth = 1
        header.addSubview(title)
        header.addSubview(subtitle)
        header.addSubview(headerStatus)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 13),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            headerStatus.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            headerStatus.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerStatus.heightAnchor.constraint(equalToConstant: 24),
            headerStatus.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.orientation = .vertical
        bodyStack.alignment = .width
        bodyStack.spacing = 12
        documentView.addSubview(bodyStack)

        addSubview(header)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 68),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            bodyStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 4),
            bodyStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -4),
            bodyStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            bodyStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -14),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -8),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
        ])
    }

    private func render() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.render() }
            return
        }
        bodyStack.arrangedSubviews.forEach {
            bodyStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        headerStatus.stringValue = "●  (currentSummary.status)"
        headerStatus.textColor = statusColor(currentSummary.status)
        headerStatus.layer?.borderColor = statusColor(currentSummary.status).withAlphaComponent(0.35).cgColor
        headerStatus.layer?.backgroundColor = statusColor(currentSummary.status).withAlphaComponent(0.10).cgColor

        bodyStack.addArrangedSubview(makeTaskCard())
        bodyStack.addArrangedSubview(makePipelineCard())
        bodyStack.addArrangedSubview(makeCurrentWorkCard())
        bodyStack.addArrangedSubview(makeRecentWorkCard())
        bodyStack.addArrangedSubview(makeVerificationCard())
        if !currentSummary.files.isEmpty {
            bodyStack.addArrangedSubview(makeFilesCard())
        }
        if currentSummary.github != nil {
            bodyStack.addArrangedSubview(makeGitHubCard())
        }
        bodyStack.addArrangedSubview(makeRuntimeCard())
        documentView.needsLayout = true
        documentView.layoutSubtreeIfNeeded()
        refreshElapsed()
    }

    private func makeTaskCard() -> NSView {
        let task = wrappingLabel(currentSummary.taskTitle.isEmpty ? "未命名任务" : currentSummary.taskTitle, size: 18, weight: .semibold, color: NSColor(calibratedWhite: 0.96, alpha: 1), lines: 2)
        let project = label("项目  (currentSummary.projectName)", size: 11, color: Palette.secondaryText)
        project.toolTip = currentSummary.projectPath
        let elapsed = label("耗时  —", size: 11, color: Palette.secondaryText)
        elapsedLabel = elapsed
        let status = pill(currentSummary.status, color: statusColor(currentSummary.status))
        let meta = NSStackView(views: [project, elapsed, status])
        meta.orientation = .horizontal
        meta.alignment = .centerY
        meta.spacing = 14
        let stack = verticalStack([task, meta], spacing: 9)
        return sectionCard("当前任务", stack, accent: Palette.accent)
    }

    private func makePipelineCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 8
        for stage in currentSummary.stages {
            let card = LayerView(fillColor: stageFill(stage.state), cornerRadius: 10, strokeColor: stageBorder(stage.state))
            card.translatesAutoresizingMaskIntoConstraints = false
            let name = label(stage.name, size: 11, weight: .semibold, color: stageText(stage.state))
            let detail = label(stage.detail, size: 10, color: stageColor(stage.state))
            name.translatesAutoresizingMaskIntoConstraints = false
            detail.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(name)
            card.addSubview(detail)
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                name.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
                detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
                detail.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
                detail.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8),
            ])
            stack.addArrangedSubview(card)
        }
        return sectionCard("Agent Pipeline · 当前阶段：\(currentSummary.currentStage)", stack, accent: Palette.violet)
    }

    private func makeCurrentWorkCard() -> NSView {
        let action = pill(currentSummary.actionType, color: actionColor(currentSummary.actionType))
        let target = label(currentSummary.target.isEmpty ? "暂无活动" : currentSummary.target, size: 14, weight: .semibold, color: NSColor(calibratedWhite: 0.95, alpha: 1))
        target.toolTip = currentSummary.targetPath
        let heading = NSStackView(views: [action, target])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 9

        var rows: [NSView] = [heading]
        if let path = currentSummary.targetPath, !path.isEmpty {
            rows.append(label(path, size: 10.5, color: Palette.secondaryText))
        }
        rows.append(keyValueRow("目的", currentSummary.purpose, color: Palette.secondaryText))
        rows.append(keyValueRow("当前操作", currentSummary.activity, color: NSColor(calibratedWhite: 0.92, alpha: 0.95)))
        let stack = verticalStack(rows, spacing: 8)
        return sectionCard("现在正在做", stack, accent: Palette.accent, emphasized: true)
    }

    private func makeRecentWorkCard() -> NSView {
        let recent = Array(currentSummary.recentActivities.prefix(5))
        let rows: [NSView]
        if recent.isEmpty {
            rows = [label("暂无最近工作", size: 12, color: Palette.secondaryText)]
        } else {
            rows = recent.map { item in
                let marker = label(statusSymbol(item.state), size: 12, weight: .bold, color: statusColor(item.state))
                marker.alignment = .center
                marker.widthAnchor.constraint(equalToConstant: 18).isActive = true
                let title = label(WorkMonitorRedaction.text(item.title, limit: 180), size: 12, weight: .medium, color: NSColor(calibratedWhite: 0.91, alpha: 0.94))
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .firstBaseline
                row.spacing = 6
                row.addArrangedSubview(marker)
                row.addArrangedSubview(title)
                if let detail = item.detail, !detail.isEmpty {
                    let detailLabel = label(WorkMonitorRedaction.text(detail, limit: 110), size: 10.5, color: Palette.secondaryText)
                    row.addArrangedSubview(detailLabel)
                }
                return row
            }
        }
        return sectionCard("最近工作", verticalStack(rows, spacing: 7), accent: Palette.blue)
    }

    private func makeVerificationCard() -> NSView {
        let items = currentSummary.verificationItems.isEmpty ? WorkActivitySummary.defaultVerification : currentSummary.verificationItems
        let rows = items.prefix(8).map { item -> NSView in
            let marker = label(statusSymbol(item.state), size: 12, weight: .bold, color: statusColor(item.state))
            marker.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let name = label(item.name, size: 11.5, weight: .medium, color: NSColor(calibratedWhite: 0.90, alpha: 0.94))
            let status = label(item.statusText, size: 10.5, color: statusColor(item.state))
            status.alignment = .right
            status.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [marker, name, status])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            return row
        }
        return sectionCard("验证状态", verticalStack(Array(rows), spacing: 7), accent: Palette.success)
    }

    private func makeFilesCard() -> NSView {
        let visible = Array(currentSummary.files.prefix(3))
        var rows = visible.map { file -> NSView in
            let marker = label(file.marker, size: 12, weight: .bold, color: file.marker == "A" ? Palette.success : file.marker == "D" ? Palette.error : Palette.accent)
            marker.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let name = label(file.name, size: 11.5, weight: .medium, color: NSColor(calibratedWhite: 0.92, alpha: 0.95))
            let row = NSStackView(views: [marker, name])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            if let path = file.path, !path.isEmpty {
                let pathLabel = label(path, size: 10, color: Palette.secondaryText)
                pathLabel.toolTip = path
                row.addArrangedSubview(pathLabel)
            }
            return row
        }
        if currentSummary.files.count > visible.count {
            rows.append(label("+ (currentSummary.files.count - visible.count) 个文件", size: 10.5, color: Palette.secondaryText))
        }
        return sectionCard("涉及文件", verticalStack(rows, spacing: 7), accent: Palette.violet)
    }

    private func makeGitHubCard() -> NSView {
        guard let github = currentSummary.github else { return sectionCard("GitHub", label("暂无 GitHub 工作", size: 11, color: Palette.secondaryText), accent: Palette.blue) }
        var rows: [NSView] = []
        if let repository = github.repository { rows.append(keyValueRow("Repository", repository, color: Palette.secondaryText)) }
        if let issue = github.issue { rows.append(keyValueRow("Issue", issue, color: Palette.secondaryText)) }
        if let branch = github.branch { rows.append(keyValueRow("Branch", branch, color: Palette.secondaryText)) }
        if let pullRequest = github.pullRequest { rows.append(keyValueRow("PR", pullRequest, color: Palette.secondaryText)) }
        if let ci = github.ci { rows.append(keyValueRow("CI", ci, color: statusColor(github.state))) }
        return sectionCard("GitHub", verticalStack(rows.isEmpty ? [label("暂无公开 GitHub 标识", size: 11, color: Palette.secondaryText)] : rows, spacing: 6), accent: Palette.blue)
    }

    private func makeRuntimeCard() -> NSView {
        let core = pill("Core  ·  \(currentSummary.coreStatus)", color: runtimeColor(currentSummary.coreStatus))
        let model = pill("模型  ·  \(currentSummary.modelStatus)", color: runtimeColor(currentSummary.modelStatus))
        let agent = pill("\(currentSummary.agentStatus)", color: runtimeColor(currentSummary.agentStatus))
        let stack = NSStackView(views: [core, model, agent])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return sectionCard("Runtime Status", stack, accent: Palette.secondaryText)
    }

    private func sectionCard(_ title: String, _ content: NSView, accent: NSColor, emphasized: Bool = false) -> NSView {
        let card = LayerView(
            fillColor: emphasized ? Palette.elevated.withAlphaComponent(0.72) : Palette.elevated.withAlphaComponent(0.48),
            cornerRadius: emphasized ? 16 : 12,
            strokeColor: accent.withAlphaComponent(emphasized ? 0.42 : 0.20)
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = label(title, size: emphasized ? 12.5 : 11.5, weight: .semibold, color: accent.withAlphaComponent(0.94))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = spacing
        return stack
    }

    private func keyValueRow(_ key: String, _ value: String, color: NSColor) -> NSStackView {
        let keyLabel = label(key, size: 10.5, weight: .semibold, color: Palette.secondaryText)
        keyLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let valueLabel = wrappingLabel(WorkMonitorRedaction.text(value, limit: 300), size: 11.5, color: color, lines: 3)
        let row = NSStackView(views: [keyLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    private func wrappingLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    private func pill(_ text: String, color: NSColor) -> NSTextField {
        let field = label(text, size: 10.5, weight: .medium, color: color)
        field.alignment = .center
        field.wantsLayer = true
        field.layer?.cornerRadius = 10
        field.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = color.withAlphaComponent(0.28).cgColor
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    private func refreshElapsed() {
        guard let elapsedLabel else { return }
        guard let since = currentSummary.elapsedSince else {
            elapsedLabel.stringValue = "耗时  —"
            return
        }
        let seconds = max(0, Int(Date().timeIntervalSince(since)))
        elapsedLabel.stringValue = String(format: "耗时  %02d:%02d", seconds / 60, seconds % 60)
    }

    private func statusSymbol(_ state: WorkMonitorItemState) -> String {
        switch state {
        case .success: return "✓"
        case .active: return "●"
        case .pending: return "○"
        case .warning: return "!"
        case .failed: return "×"
        }
    }

    private func statusColor(_ value: String) -> NSColor {
        let lowered = value.lowercased()
        if lowered.contains("失败") || lowered.contains("fail") || lowered.contains("断开") { return Palette.error }
        if lowered.contains("警告") || lowered.contains("配置") || lowered.contains("恢复") || lowered.contains("等待") { return Palette.warning }
        if lowered.contains("完成") || lowered.contains("pass") || lowered.contains("ready") || lowered.contains("就绪") { return Palette.success }
        if lowered.contains("工作") || lowered.contains("运行") || lowered.contains("active") { return Palette.accent }
        return Palette.secondaryText
    }

    private func statusColor(_ state: WorkMonitorItemState) -> NSColor {
        switch state {
        case .success: return Palette.success
        case .active: return Palette.accent
        case .pending: return Palette.secondaryText
        case .warning: return Palette.warning
        case .failed: return Palette.error
        }
    }

    private func stageColor(_ state: WorkMonitorItemState) -> NSColor { statusColor(state) }

    private func stageFill(_ state: WorkMonitorItemState) -> NSColor {
        stageColor(state).withAlphaComponent(state == .active ? 0.18 : 0.08)
    }

    private func stageBorder(_ state: WorkMonitorItemState) -> NSColor {
        stageColor(state).withAlphaComponent(state == .active ? 0.52 : 0.22)
    }

    private func stageText(_ state: WorkMonitorItemState) -> NSColor {
        state == .pending ? NSColor(calibratedWhite: 0.72, alpha: 0.82) : NSColor(calibratedWhite: 0.95, alpha: 1)
    }

    private func actionColor(_ action: String) -> NSColor {
        let lowered = action.lowercased()
        if lowered.contains("验证") || lowered.contains("运行") { return Palette.success }
        if lowered.contains("github") || lowered.contains("浏览器") { return Palette.violet }
        if lowered.contains("等待") || lowered.contains("恢复") { return Palette.warning }
        return Palette.accent
    }

    private func runtimeColor(_ value: String) -> NSColor { statusColor(value) }
}
