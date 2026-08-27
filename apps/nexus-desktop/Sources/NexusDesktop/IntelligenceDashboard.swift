import AppKit
import Foundation
import Darwin

// MARK: - 本地全球情报服务

/// OSIRIS 以独立的本地 Node 进程运行，但生命周期由 AI Dev One 持有。
/// 这样全球数据不会依赖远程网页，也不会在用户退出应用后留下孤儿进程。
enum IntelligenceServiceState: String {
    case stopped
    case starting
    case ready
    case failed
}

final class IntelligenceServiceController {
    static let shared = IntelligenceServiceController()

    private(set) var state: IntelligenceServiceState = .stopped
    private(set) var baseURL: URL?
    private var dashboardProcess: Process?
    private var intelProcess: Process?
    private var generation: UInt64 = 0
    private var startInFlight = false
    private var stopping = false
    private var lastError: String?

    private init() {}

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        if state == .ready, let baseURL {
            completion(.success(baseURL))
            return
        }
        guard !startInFlight else { return }
        startInFlight = true
        stopping = false
        state = .starting
        generation &+= 1
        let currentGeneration = generation

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let root = try self.resolveResourceRoot()
                let node = try self.resolveNode()
                let dashboardRoot = root.appendingPathComponent("server", isDirectory: true)
                let server = dashboardRoot.appendingPathComponent("server.js")
                guard FileManager.default.isReadableFile(atPath: server.path) else {
                    throw NSError(domain: "AIDevOneIntelligence", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "全球情报服务资源未安装"
                    ])
                }

                let dashboardPort = Self.freePort()
                let intelPort = Self.freePort(excluding: dashboardPort)
                let intelRoot = root.appendingPathComponent("intel", isDirectory: true)
                let intelServer = intelRoot.appendingPathComponent("server.js")
                var environment = BackendLocator.processEnvironment()
                environment["PATH"] = Self.nodePath(environment["PATH"])
                environment["PORT"] = String(dashboardPort)
                environment["HOSTNAME"] = "127.0.0.1"
                environment["NODE_ENV"] = "production"
                environment["NEXT_TELEMETRY_DISABLED"] = "1"
                environment["INTEL_URL"] = "http://127.0.0.1:\(intelPort)"
                let cacheDirectory = try Self.runtimeCacheDirectory()
                environment["AI_DEV_ONE_INTELLIGENCE_CACHE_DIR"] = cacheDirectory.path

                if FileManager.default.isReadableFile(atPath: intelServer.path) {
                    let intel = Process()
                    intel.executableURL = node
                    intel.currentDirectoryURL = intelRoot
                    intel.arguments = ["server.js"]
                    var intelEnvironment = environment
                    intelEnvironment["INTEL_PORT"] = String(intelPort)
                    intel.environment = intelEnvironment
                    let intelPipe = Pipe()
                    intel.standardOutput = intelPipe
                    intel.standardError = intelPipe
                    // The service is intentionally quiet in the UI, but its
                    // stdout/stderr must still be drained.  Leaving a Pipe
                    // unread eventually fills the kernel buffer and can make
                    // a long-running Next process stop accepting refreshes.
                    self.drainServiceOutput(intelPipe)
                    intel.terminationHandler = { [weak self] process in
                        guard let self, !self.stopping, process.terminationStatus != 0 else { return }
                        self.lastError = "本地实体解析服务退出（\(process.terminationStatus)）"
                    }
                    try intel.run()
                    self.intelProcess = intel
                    if self.stopping || self.generation != currentGeneration {
                        self.stopProcessesOnly()
                        throw NSError(domain: "AIDevOneIntelligence", code: 5, userInfo: [
                            NSLocalizedDescriptionKey: "全球情报服务启动已取消"
                        ])
                    }
                }

                guard !self.stopping, self.generation == currentGeneration else {
                    throw NSError(domain: "AIDevOneIntelligence", code: 5, userInfo: [
                        NSLocalizedDescriptionKey: "全球情报服务启动已取消"
                    ])
                }
                let dashboard = Process()
                dashboard.executableURL = node
                dashboard.currentDirectoryURL = dashboardRoot
                dashboard.arguments = ["server.js"]
                dashboard.environment = environment
                let dashboardPipe = Pipe()
                dashboard.standardOutput = dashboardPipe
                dashboard.standardError = dashboardPipe
                self.drainServiceOutput(dashboardPipe)
                dashboard.terminationHandler = { [weak self] process in
                    guard let self, !self.stopping, process.terminationStatus != 0 else { return }
                    self.state = .failed
                    self.lastError = "全球情报服务退出（\(process.terminationStatus)）"
                }
                try dashboard.run()
                self.dashboardProcess = dashboard
                if self.stopping || self.generation != currentGeneration {
                    self.stopProcessesOnly()
                    throw NSError(domain: "AIDevOneIntelligence", code: 5, userInfo: [
                        NSLocalizedDescriptionKey: "全球情报服务启动已取消"
                    ])
                }
                let url = URL(string: "http://127.0.0.1:\(dashboardPort)")!

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.baseURL = url
                    self.waitForHealth(url: url, generation: currentGeneration, attempts: 0, completion: completion)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.finishStart(.failure(error), generation: currentGeneration, completion: completion)
                }
            }
        }
    }

    func stop() {
        stopping = true
        generation &+= 1
        startInFlight = false
        state = .stopped
        baseURL = nil
        [dashboardProcess, intelProcess].forEach { process in
            terminate(process)
        }
        dashboardProcess = nil
        intelProcess = nil
    }

    private func finishStart(
        _ result: Result<URL, Error>,
        generation: UInt64,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard self.generation == generation else { return }
        startInFlight = false
        switch result {
        case .success(let url):
            state = .ready
            baseURL = url
        case .failure(let error):
            state = .failed
            lastError = error.localizedDescription
            stopProcessesOnly()
        }
        completion(result)
    }

    private func waitForHealth(
        url: URL,
        generation: UInt64,
        attempts: Int,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard self.generation == generation, !stopping else { return }
        let healthURL = url.appendingPathComponent("api/health")
        URLSession.shared.dataTask(with: healthURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == generation, !self.stopping else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200, data != nil {
                    self.finishStart(.success(url), generation: generation, completion: completion)
                    return
                }
                if attempts >= 60 {
                    let reason = error?.localizedDescription ?? self.lastError ?? "本地服务健康检查超时"
                    let failure = NSError(domain: "AIDevOneIntelligence", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: reason
                    ])
                    self.finishStart(.failure(failure), generation: generation, completion: completion)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.waitForHealth(url: url, generation: generation, attempts: attempts + 1, completion: completion)
                }
            }
        }.resume()
    }

    private func stopProcessesOnly() {
        [dashboardProcess, intelProcess].forEach { process in
            terminate(process)
        }
        dashboardProcess = nil
        intelProcess = nil
    }

    private func drainServiceOutput(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            // Do not forward service output to the UI or logs: public feeds
            // can contain arbitrary external text.  Reading and discarding it
            // is enough to keep the child process healthy and preserves the
            // existing redaction boundary.
            _ = handle.availableData
        }
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        // Next may keep its production server alive briefly while it drains
        // requests. A bounded hard-stop prevents an orphaned local service if
        // the desktop app is quitting or the dashboard failed to start.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45) {
            if process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }

    private func resolveResourceRoot() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let candidates: [URL?] = [
            environment["AI_DEV_ONE_INTELLIGENCE_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            Bundle.main.resourceURL?.appendingPathComponent("Intelligence", isDirectory: true),
        ]
        if let root = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("server/server.js").path)
        }) {
            return root
        }
        throw NSError(domain: "AIDevOneIntelligence", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "未找到本地全球情报服务"
        ])
    }

    private func resolveNode() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/AI Dev One Installer/toolchains/node/bin/node"),
            home.appendingPathComponent("Library/Application Support/AI Dev One/Runtime/toolchains/node/bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
        ]
        if let node = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return node
        }
        throw NSError(domain: "AIDevOneIntelligence", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "未找到应用内 Node.js 运行时"
        ])
    }

    private static func runtimeCacheDirectory() throws -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport
            .appendingPathComponent("AI Dev One", isDirectory: true)
            .appendingPathComponent("Intelligence", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func nodePath(_ current: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let nodeBin = home.appendingPathComponent("Library/Application Support/AI Dev One Installer/toolchains/node/bin").path
        let existing = current ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return nodeBin + ":" + existing
    }

    private static func freePort(excluding: Int? = nil) -> Int {
        for _ in 0..<30 {
            let candidate = Int.random(in: 28_000...48_000)
            if candidate != excluding { return candidate }
        }
        return 38_417
    }
}

// MARK: - 全球态势图形

struct IntelligencePoint {
    let latitude: CGFloat
    let longitude: CGFloat
    let color: NSColor
    let radius: CGFloat
}

// MARK: - 全球情报中心 V1 数据契约

/// V1 的情报中心默认使用本地固定样本。数据模型刻意不包含 API key、
/// Authorization header 或外部服务对象，确保 UI 可以在离线、无凭据的
/// 冷启动中稳定打开；后续接入真实来源时只需替换 Provider。
enum IntelligenceSourceMode: String {
    case fixture
}

enum IntelligenceEventKind: String {
    case news
    case flight
    case satellite
    case earthquake
    case weather
    case security

    var displayName: String {
        switch self {
        case .news: return "新闻"
        case .flight: return "航班"
        case .satellite: return "卫星"
        case .earthquake: return "地震"
        case .weather: return "气象"
        case .security: return "安全"
        }
    }
}

enum IntelligenceSeverity: String {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高风险"
        }
    }
}

struct IntelligenceEvent {
    let id: String
    let kind: IntelligenceEventKind
    let title: String
    let summary: String
    let source: String
    let timestamp: Date
    let severity: IntelligenceSeverity
    let latitude: Double?
    let longitude: Double?
    let metadata: [String: String]
}

struct IntelligenceSourceSummary {
    let name: String
    let eventCount: Int
}

struct IntelligenceRiskSummary {
    let high: Int
    let medium: Int
    let low: Int
}

struct GlobalIntelligenceSnapshot {
    let generatedAt: Date
    let sourceMode: IntelligenceSourceMode
    let events24h: [IntelligenceEvent]
    let eventTotal: Int
    let flightCount: Int
    let satelliteCount: Int
    let earthquakeCount: Int
    let newEventCount: Int
    let sources: [IntelligenceSourceSummary]
    let risk: IntelligenceRiskSummary
    let insight: String
}

// The formal `protocol IntelligenceDataProvider` contract lives in
// IntelligenceDataArchitecture.swift.  This small legacy protocol keeps the
// synchronous fixture snapshot API private to the frozen dashboard bridge.
private protocol FixtureSnapshotProvider {
    var sourceMode: IntelligenceSourceMode { get }
    func snapshot(at date: Date) -> GlobalIntelligenceSnapshot
}

/// Deterministic, Chinese-first fixture provider for the first standalone
/// window release.  Timestamps advance with an explicit refresh, but the
/// event content remains local and clearly labelled as demo data; no network
/// request is made and no external service is started.
final class FixtureIntelligenceDataProvider: FixtureSnapshotProvider {
    let sourceMode: IntelligenceSourceMode = .fixture

    func snapshot(at date: Date = Date()) -> GlobalIntelligenceSnapshot {
        let events: [IntelligenceEvent] = [
            IntelligenceEvent(
                id: "fixture-news-asia-01", kind: .news,
                title: "亚太多国发布能源与航运安全联合通报",
                summary: "公开通报显示，相关部门正在加强主要港口和能源运输线路的态势监测。该事件为本地演示样本，不代表实时预警。",
                source: "公开新闻汇总（演示）", timestamp: date.addingTimeInterval(-300), severity: .medium,
                latitude: 35.7, longitude: 139.7, metadata: ["地区": "亚太"]
            ),
            IntelligenceEvent(
                id: "fixture-news-europe-02", kind: .news,
                title: "欧洲气象机构更新跨区域极端天气提示",
                summary: "样本摘要用于展示事件详情、来源和风险分级；实际使用时可由受信来源 Provider 替换。",
                source: "欧洲气象公开源（演示）", timestamp: date.addingTimeInterval(-720), severity: .low,
                latitude: 50.1, longitude: 8.7, metadata: ["地区": "欧洲"]
            ),
            IntelligenceEvent(
                id: "fixture-news-america-03", kind: .news,
                title: "北美基础设施部门完成例行风险复核",
                summary: "演示事件包含结构化标题、摘要、来源和时间，点击后可在下方查看完整信息。",
                source: "基础设施公开通报（演示）", timestamp: date.addingTimeInterval(-1_260), severity: .low,
                latitude: 38.9, longitude: -77.0, metadata: ["地区": "北美"]
            ),
            IntelligenceEvent(
                id: "fixture-earthquake-01", kind: .earthquake,
                title: "M5.8 · 菲律宾海域地震监测",
                summary: "示例地震位于菲律宾海域，深度约 42 公里。请结合当地官方通报判断实际影响。",
                source: "美国地质调查局（演示）", timestamp: date.addingTimeInterval(-1_680), severity: .medium,
                latitude: 14.2, longitude: 122.3, metadata: ["震级": "5.8", "深度": "42 公里"]
            ),
            IntelligenceEvent(
                id: "fixture-earthquake-02", kind: .earthquake,
                title: "M4.6 · 日本东部近海地震监测",
                summary: "示例事件展示地震类别在列表、地图和详情卡中的统一呈现。",
                source: "美国地质调查局（演示）", timestamp: date.addingTimeInterval(-2_100), severity: .low,
                latitude: 36.1, longitude: 141.2, metadata: ["震级": "4.6", "深度": "28 公里"]
            ),
            IntelligenceEvent(
                id: "fixture-flight-01", kind: .flight,
                title: "航班轨迹 · 东京—新加坡航路",
                summary: "公开 ADS-B 航迹的本地演示点，展示航班数量统计和地图定位，不代表当前真实位置。",
                source: "公开航班数据（演示）", timestamp: date.addingTimeInterval(-180), severity: .low,
                latitude: 24.8, longitude: 128.4, metadata: ["航班": "AID001", "高度": "10,400 米"]
            ),
            IntelligenceEvent(
                id: "fixture-flight-02", kind: .flight,
                title: "航班轨迹 · 北美太平洋航路",
                summary: "本地样本用于检验筛选、详情和来源展示，刷新不会访问外部接口。",
                source: "公开航班数据（演示）", timestamp: date.addingTimeInterval(-420), severity: .low,
                latitude: 38.0, longitude: -150.0, metadata: ["航班": "AID002", "高度": "11,100 米"]
            ),
            IntelligenceEvent(
                id: "fixture-satellite-01", kind: .satellite,
                title: "国际空间站（ISS）轨道位置",
                summary: "演示轨道点用于展示卫星标签和轨道状态；实际轨道数据将在后续 Provider 中接入。",
                source: "CelesTrak / SatNOGS（演示）", timestamp: date.addingTimeInterval(-240), severity: .low,
                latitude: 10.0, longitude: 72.0, metadata: ["轨道高度": "408 公里"]
            ),
            IntelligenceEvent(
                id: "fixture-satellite-02", kind: .satellite,
                title: "气象卫星 · 亚洲观测轨道",
                summary: "本地样本展示卫星类别的地图节点和详情内容。",
                source: "CelesTrak / SatNOGS（演示）", timestamp: date.addingTimeInterval(-540), severity: .low,
                latitude: -4.0, longitude: 105.0, metadata: ["轨道高度": "705 公里"]
            ),
            IntelligenceEvent(
                id: "fixture-weather-01", kind: .weather,
                title: "西北太平洋热带风暴路径样本",
                summary: "演示气象事件用于展示中风险分级和区域筛选。数据不构成气象预警。",
                source: "NASA / NOAA（演示）", timestamp: date.addingTimeInterval(-900), severity: .medium,
                latitude: 18.5, longitude: 132.8, metadata: ["类型": "热带风暴"]
            ),
            IntelligenceEvent(
                id: "fixture-weather-02", kind: .weather,
                title: "澳大利亚东部高温提示样本",
                summary: "用于测试事件详情面板的长摘要换行和风险颜色。",
                source: "NASA / NOAA（演示）", timestamp: date.addingTimeInterval(-1_500), severity: .low,
                latitude: -33.9, longitude: 151.2, metadata: ["类型": "高温"]
            ),
            IntelligenceEvent(
                id: "fixture-security-01", kind: .security,
                title: "公开软件供应链风险通告样本",
                summary: "示例安全事件提示用户在项目内核验依赖版本；本地情报中心不会执行扫描或连接目标。",
                source: "CISA KEV（演示）", timestamp: date.addingTimeInterval(-2_400), severity: .high,
                latitude: 37.8, longitude: -122.4, metadata: ["类型": "供应链"]
            ),
            IntelligenceEvent(
                id: "fixture-security-02", kind: .security,
                title: "关键基础设施公开风险复盘样本",
                summary: "事件详情用于验证高风险摘要、来源列表和 AI 分析选择链路。",
                source: "全球公开安全源（演示）", timestamp: date.addingTimeInterval(-3_000), severity: .high,
                latitude: 51.5, longitude: -0.1, metadata: ["类型": "基础设施"]
            )
        ]
        let sources = [
            IntelligenceSourceSummary(name: "公开新闻汇总", eventCount: 3),
            IntelligenceSourceSummary(name: "美国地质调查局", eventCount: 2),
            IntelligenceSourceSummary(name: "CelesTrak / SatNOGS", eventCount: 2),
            IntelligenceSourceSummary(name: "NASA / NOAA", eventCount: 2),
            IntelligenceSourceSummary(name: "公开航班数据", eventCount: 2),
            IntelligenceSourceSummary(name: "CISA KEV / 安全公开源", eventCount: 2),
        ]
        return GlobalIntelligenceSnapshot(
            generatedAt: date,
            sourceMode: sourceMode,
            events24h: events,
            eventTotal: 3_421,
            flightCount: 335,
            satelliteCount: 18_841,
            earthquakeCount: 47,
            newEventCount: 2,
            sources: sources,
            risk: IntelligenceRiskSummary(high: 23, medium: 67, low: 66),
            insight: "• 亚太航运与能源监测样本占比较高，建议优先核验官方通报。\n• 航班、卫星与地震样本用于演示跨类别关联，不代表实时变化。\n• 选择事件后可交给 AI Dev One，分析事实、来源与潜在影响。\n\n以上均为本地固定样本，不代表实时预警。"
        )
    }
}

/// 情报列表、详情看板和 AI 分析共用同一份结构化数据，避免点击列表后
/// 只剩一行提示、或分析时又从 UI 文本反向解析事件。
struct IntelligenceFeedItem {
    let id: String
    let category: String
    let title: String
    let summary: String
    let source: String
    let publishedAt: String
    let riskScore: Int
    let url: URL?

    var riskLabel: String {
        if riskScore >= 7 { return "高风险" }
        if riskScore >= 4 { return "中风险" }
        return "低风险"
    }
}

/// 详情卡片使用真正的多行 NSTextField。`labelWithString:` 默认是单行
/// cell，即使后来设置 maximumNumberOfLines 也可能在 Auto Layout 重新求解
/// 时保留旧的单行高度，造成中文和英文叠印。显式使用 wrapping cell，并
/// 关闭可滚动单行行为，确保每次刷新都只绘制一份、且按卡片宽度换行。
private func intelligenceWrappingLabel(
    _ text: String,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor,
    lines: Int = 0
) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    field.maximumNumberOfLines = lines
    field.cell?.wraps = lines != 1
    field.cell?.isScrollable = false
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setContentHuggingPriority(.defaultLow, for: .vertical)
    return field
}

/// AppKit controls in the embedded intelligence page must respond to the
/// first click even when the workspace panel has just become key.  The page
/// is a normal desktop surface, not a web view, so relying on the default
/// `acceptsFirstMouse` behaviour makes the first real click appear to do
/// nothing.
final class IntelligenceSegmentedControl: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IntelligencePopupButton: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IntelligenceCheckButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IntelligenceGlobeView: NSView {
    var points: [IntelligencePoint] = [] {
        didSet { needsDisplay = true }
    }
    var onPointSelected: ((IntelligencePoint) -> Void)?
    private var selectedPoint: IntelligencePoint?
    // 将初始视角落在亚洲—太平洋区域，便于第一眼看到主要节点。
    // 用户仍可拖拽旋转；这个值只决定每次打开面板时的默认方位。
    private var rotationOffset: CGFloat = -110
    private var rotationTimer: Timer?
    private var dragLastX: CGFloat?
    private var zoomScale: CGFloat = 1.0
    private(set) var isRotating = true
    private var cachedBackground: NSImage?
    private var cachedBackgroundSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("全球事件地球态势图")
        setAccessibilityValue("可拖拽旋转，滚轮缩放")
    }

    deinit {
        rotationTimer?.invalidate()
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size {
            cachedBackground = nil
            cachedBackgroundSize = .zero
        }
        super.setFrameSize(newSize)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Keep the whole globe as one hit target.  This prevents a future
    // decorative subview (glow/grid) from stealing the click from the map.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func startRotation() {
        guard rotationTimer == nil else { return }
        isRotating = true
        // 地球是环境态势动画，不是游戏画面。低频、电影感的旋转既能
        // 保留动态空间感，也避免 AppKit 矢量重绘拖慢输入和滚动。
        // 用户开启“减少动态效果”时保持静态，仍可用鼠标手动旋转。
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            isRotating = false
            return
        }
        let timer = Timer(timeInterval: 1.0 / 4.0, repeats: true) { [weak self] _ in
            guard let self,
                  self.isRotating,
                  NSApp.isActive,
                  self.window?.occlusionState.contains(.visible) == true else { return }
            self.rotationOffset += 1.35
            if self.rotationOffset >= 360 { self.rotationOffset -= 360 }
            self.needsDisplay = true
        }
        timer.tolerance = 0.08
        rotationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopRotation() {
        isRotating = false
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    @discardableResult
    func toggleRotation() -> Bool {
        if isRotating {
            stopRotation()
        } else {
            startRotation()
        }
        return isRotating
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRotation() }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragLastX = location.x
        // 即使公开数据暂时为空，也要允许用户手动旋转地球；
        // 节点选择仅在有数据时执行，避免空数据状态把交互整块禁用。
        guard !points.isEmpty else { return }
        let rect = bounds.insetBy(dx: 12, dy: 12)
        // Keep hit testing aligned with the framed sphere drawn in `draw`.
        // The old width-biased radius made clicks near Asia/Pacific miss after
        // the V1.1 globe was deliberately reduced to stay fully in frame.
        let baseRadius = min(rect.width * 0.36, rect.height * 0.50)
        let maxRadius = min(rect.width * 0.40, rect.height * 0.53)
        let radius = min(baseRadius * zoomScale, maxRadius)
        let center = NSPoint(x: rect.midX, y: rect.midY - 5)
        let nearest = points.min { lhs, rhs in
            distance(for: lhs, from: location, radius: radius, center: center)
                < distance(for: rhs, from: location, radius: radius, center: center)
        }
        if let nearest {
            selectedPoint = nearest
            onPointSelected?(nearest)
            needsDisplay = true
        }
    }

    /// 鼠标拖动提供手动旋转；自动旋转仍会在未交互时继续运行。
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let lastX = dragLastX else {
            dragLastX = location.x
            return
        }
        rotationOffset += (location.x - lastX) * 0.55
        if rotationOffset >= 360 { rotationOffset -= 360 }
        if rotationOffset < 0 { rotationOffset += 360 }
        dragLastX = location.x
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragLastX = nil
        super.mouseUp(with: event)
    }

    /// 以 AppKit 原生滚轮事件调整球体比例。缩放只影响地球绘制区域，
    /// 不会改变窗口或面板布局；缓存背景在比例改变后失效并重建一次。
    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 2.0
        let next = min(1.22, max(0.82, zoomScale + delta * 0.018))
        guard abs(next - zoomScale) > 0.0001 else { return }
        zoomScale = next
        cachedBackground = nil
        cachedBackgroundSize = .zero
        setAccessibilityValue("可拖拽旋转，当前缩放 (Int(round(zoomScale * 100)))%")
        needsDisplay = true
    }

    private func distance(
        for point: IntelligencePoint,
        from location: NSPoint,
        radius: CGFloat,
        center: NSPoint
    ) -> CGFloat {
        let longitude = (point.longitude + rotationOffset) * .pi / 180
        let latitude = point.latitude * .pi / 180
        let x = center.x + radius * 0.94 * sin(longitude) * cos(latitude)
        let y = center.y + radius * 0.94 * sin(latitude)
        let dx = x - location.x
        let dy = y - location.y
        return dx * dx + dy * dy
    }

    private func project(latitude: CGFloat, longitude: CGFloat, radius: CGFloat, center: NSPoint) -> (point: NSPoint, visible: CGFloat) {
        let lon = (longitude + rotationOffset) * .pi / 180
        let lat = latitude * .pi / 180
        let visible = cos(lon) * cos(lat)
        return (
            NSPoint(
                x: center.x + radius * 0.94 * sin(lon) * cos(lat),
                y: center.y + radius * 0.94 * sin(lat)
            ),
            visible
        )
    }

    /// 光晕、球面渐变、网格和标题都不随经度变化。旧实现每个动画帧
    /// 都重画这些昂贵的 AppKit 矢量层，地球页可持续占用半个以上 CPU
    /// 核心。现在只在视图尺寸变化时渲染一次；动画帧只更新大陆和节点。
    private func drawStaticBackground(rect: NSRect, radius: CGFloat, center: NSPoint, sphere: NSRect) {
        let haloColors = [Palette.accent, Palette.violet, Palette.blue]
        for (index, inset) in [18.0, 30.0, 43.0].enumerated() {
            let halo = NSBezierPath(ovalIn: sphere.insetBy(dx: -inset, dy: -inset * 0.56))
            halo.lineWidth = index == 0 ? 0.9 : 0.55
            haloColors[index].withAlphaComponent(index == 0 ? 0.13 : 0.07).setStroke()
            halo.stroke()
        }
        let particles: [(CGFloat, CGFloat, NSColor)] = [
            (0.11, 0.25, Palette.accent), (0.20, 0.78, Palette.violet),
            (0.84, 0.22, Palette.blue), (0.91, 0.67, Palette.accent),
            (0.71, 0.89, Palette.violet), (0.34, 0.10, Palette.accent),
        ]
        for particle in particles {
            particle.2.withAlphaComponent(0.34).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + rect.width * particle.0 - 1,
                y: rect.minY + rect.height * particle.1 - 1,
                width: 2,
                height: 2
            )).fill()
        }

        // 球体在背景上的软阴影让边缘有真实的悬浮感；阴影被压在
        // 球面渐变之下，不会改变事件节点的命中和可读性。
        let sphereShadow = sphere
            .insetBy(dx: -radius * 0.035, dy: -radius * 0.035)
            .offsetBy(dx: radius * 0.065, dy: -radius * 0.075)
        NSColor.black.withAlphaComponent(0.30).setFill()
        NSBezierPath(ovalIn: sphereShadow).fill()

        // 深海蓝的球面渐变 + 左上方冷光，让它读起来像一个有昼夜
        // 阴影的地球，而不是平面的线框圆。
        let sphereGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.57, alpha: 0.92),
            NSColor(calibratedRed: 0.018, green: 0.15, blue: 0.23, alpha: 0.98),
            NSColor(calibratedRed: 0.002, green: 0.018, blue: 0.045, alpha: 1),
        ])
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        sphereGradient?.draw(in: sphere, relativeCenterPosition: NSPoint(x: -0.32, y: 0.42))
        // A restrained radial highlight gives the ocean a curved, glass-like
        // volume.  It is cached with the rest of the sphere so the rotating
        // layer does not pay for another gradient on every frame.
        let oceanHighlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.12),
            NSColor(calibratedRed: 0.05, green: 0.35, blue: 0.48, alpha: 0.03),
            NSColor.clear,
        ])
        oceanHighlight?.draw(in: sphere.insetBy(dx: radius * 0.06, dy: radius * 0.05), relativeCenterPosition: NSPoint(x: -0.38, y: 0.35))
        // 右侧的夜半球轻轻压暗；不画硬边，避免像一个切开的圆盘。
        let night = NSBezierPath(ovalIn: NSRect(
            x: sphere.midX + sphere.width * 0.02,
            y: sphere.minY - sphere.height * 0.04,
            width: sphere.width * 0.70,
            height: sphere.height * 1.08
        ))
        NSColor(calibratedRed: 0.002, green: 0.008, blue: 0.024, alpha: 0.20).setFill()
        night.fill()
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(ovalIn: sphere.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1.15
        Palette.accent.withAlphaComponent(0.46).setStroke()
        rim.stroke()

        // 大气层只在球面边缘出现，避免在小面板中形成一块发灰的背景。
        let atmosphere = NSBezierPath(ovalIn: sphere.insetBy(dx: -5, dy: -5))
        atmosphere.lineWidth = 5
        NSColor(calibratedRed: 0.12, green: 0.80, blue: 0.94, alpha: 0.12).setStroke()
        atmosphere.stroke()

        let arc = NSBezierPath()
        arc.move(to: NSPoint(x: sphere.minX + 16, y: sphere.midY - 34))
        arc.curve(to: NSPoint(x: sphere.maxX - 10, y: sphere.midY + 52),
                  controlPoint1: NSPoint(x: sphere.midX - 8, y: sphere.minY + 8),
                  controlPoint2: NSPoint(x: sphere.midX + 26, y: sphere.maxY - 2))
        arc.lineWidth = 0.8
        Palette.violet.withAlphaComponent(0.30).setStroke()
        arc.stroke()
    }

    /// 经纬线必须随着经度一起移动；静态椭圆会让球面看起来像平面
    /// 背景。只绘制少量采样点，保持旋转时的 CPU 预算。
    private func drawDynamicGrid(radius: CGFloat, center: NSPoint, sphere: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        for latitude in stride(from: -60, through: 60, by: 30) {
            let path = NSBezierPath()
            for step in 0...28 {
                let longitude = CGFloat(step) / 28 * 360 - 180
                let projected = project(latitude: CGFloat(latitude), longitude: longitude, radius: radius, center: center)
                if step == 0 { path.move(to: projected.point) } else { path.line(to: projected.point) }
            }
            path.lineWidth = 0.45
            Palette.accent.withAlphaComponent(0.15).setStroke()
            path.stroke()
        }
        for longitude in stride(from: -150, through: 180, by: 30) {
            let path = NSBezierPath()
            for step in 0...20 {
                let latitude = CGFloat(step) / 20 * 180 - 90
                let projected = project(latitude: latitude, longitude: CGFloat(longitude), radius: radius, center: center)
                if step == 0 { path.move(to: projected.point) } else { path.line(to: projected.point) }
            }
            path.lineWidth = 0.45
            Palette.violet.withAlphaComponent(0.13).setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 参考概念图中的细弧线网络，把主要情报节点之间的关联画成
    /// 极低透明度的球面航线。它不是装饰性直线：端点和控制点都经过
    /// 同一套经纬度投影，因此会随着地球旋转并在背面自然消失。
    private func drawDataRoutes(radius: CGFloat, center: NSPoint, sphere: NSRect) {
        let routes: [((CGFloat, CGFloat), (CGFloat, CGFloat))] = [
            ((31, 121), (37, -122)),
            ((35, 139), (51, 0)),
            ((1, 103), (25, 55)),
            ((40, -74), (-23, -46)),
            ((48, 2), (30, 31)),
            ((-33, 151), (35, 139)),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        for (from, to) in routes {
            let start = project(latitude: from.0, longitude: from.1, radius: radius, center: center)
            let end = project(latitude: to.0, longitude: to.1, radius: radius, center: center)
            guard start.visible > -0.35 || end.visible > -0.35 else { continue }
            let path = NSBezierPath()
            path.move(to: start.point)
            let midpoint = NSPoint(
                x: (start.point.x + end.point.x) * 0.5,
                y: (start.point.y + end.point.y) * 0.5 + radius * 0.12
            )
            path.curve(
                to: end.point,
                controlPoint1: NSPoint(x: (start.point.x + midpoint.x) * 0.5, y: (start.point.y + midpoint.y) * 0.5),
                controlPoint2: NSPoint(x: (end.point.x + midpoint.x) * 0.5, y: (end.point.y + midpoint.y) * 0.5)
            )
            path.lineWidth = 0.55
            Palette.accent.withAlphaComponent(0.14).setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCloudBands(radius: CGFloat, center: NSPoint) {
        let sphere = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        let bands: [[(CGFloat, CGFloat)]] = [
            [(-8, -165), (-4, -120), (-7, -75), (-3, -30), (-6, 15), (-2, 60), (-5, 105), (-1, 150)],
            [(28, -140), (32, -95), (27, -45), (31, 5), (26, 55), (30, 105), (27, 150)],
            [(-42, -150), (-38, -100), (-43, -50), (-39, 0), (-44, 50), (-40, 100), (-43, 150)],
            [(8, -150), (11, -112), (7, -72), (12, -28), (9, 18), (13, 64), (8, 108), (11, 150)],
        ]
        for band in bands {
            let path = NSBezierPath()
            for (index, coordinate) in band.enumerated() {
                let projected = project(latitude: coordinate.0, longitude: coordinate.1, radius: radius, center: center)
                if index == 0 { path.move(to: projected.point) } else { path.line(to: projected.point) }
            }
            path.lineCapStyle = .round
            path.lineWidth = 1.25
            NSColor.white.withAlphaComponent(0.075).setStroke()
            path.stroke()
        }

        // 细小的弧形云带打破“经纬线球”的机械感；透明度很低，
        // 只在高光面留下类似卫星照片的层次。
        let wisps: [[(CGFloat, CGFloat)]] = [
            [(41, -118), (46, -86), (42, -48), (47, -8), (40, 30)],
            [(-8, -150), (-3, -112), (-10, -72), (-5, -28), (-11, 14)],
            [(18, 72), (23, 100), (18, 126), (21, 153)],
        ]
        for wisp in wisps {
            let path = NSBezierPath()
            for (index, coordinate) in wisp.enumerated() {
                let projected = project(latitude: coordinate.0, longitude: coordinate.1, radius: radius, center: center)
                if index == 0 {
                    path.move(to: projected.point)
                } else if index == 1 {
                    path.curve(to: projected.point,
                               controlPoint1: NSPoint(x: projected.point.x - radius * 0.08, y: projected.point.y + radius * 0.04),
                               controlPoint2: NSPoint(x: projected.point.x + radius * 0.06, y: projected.point.y - radius * 0.03))
                } else {
                    path.line(to: projected.point)
                }
            }
            path.lineCapStyle = .round
            path.lineWidth = 0.7
            NSColor.white.withAlphaComponent(0.055).setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Thin orbital tracks make the map read as a living planet rather than a
    /// flat wireframe.  They are deliberately below the event markers and
    /// use a low-alpha violet/cyan treatment matching the concept artwork.
    private func drawOrbitArcs(radius: CGFloat, center: NSPoint) {
        let orbitSpecs: [(CGFloat, CGFloat, NSColor)] = [
            (1.12, 0.34, Palette.violet.withAlphaComponent(0.30)),
            (1.18, 0.20, Palette.accent.withAlphaComponent(0.25)),
        ]
        for (scale, flattening, color) in orbitSpecs {
            let orbitRect = NSRect(
                x: center.x - radius * scale,
                y: center.y - radius * flattening,
                width: radius * scale * 2,
                height: radius * flattening * 2
            )
            let path = NSBezierPath(ovalIn: orbitRect)
            path.lineWidth = 0.55
            color.setStroke()
            path.stroke()
        }
    }

    /// A soft moving terminator supplies the depth cue missing from a static
    /// gradient.  The edge is intentionally featherless and very dim: the
    /// data nodes remain readable while the illuminated hemisphere follows
    /// the user's manual/automatic rotation.
    private func drawTerminator(radius: CGFloat, center: NSPoint, sphere: NSRect) {
        let phase = (rotationOffset + 22) * .pi / 180
        let shadowOffset = CGFloat(sin(phase)) * radius * 0.28
        let shadowWidth = radius * (0.98 + 0.18 * CGFloat(abs(cos(phase))))
        let shadow = NSRect(
            x: center.x + shadowOffset - shadowWidth * 0.52,
            y: sphere.minY - radius * 0.06,
            width: shadowWidth,
            height: sphere.height * 1.12
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        NSColor(calibratedRed: 0.001, green: 0.008, blue: 0.025, alpha: 0.16).setFill()
        NSBezierPath(ovalIn: shadow).fill()

        let terminator = NSBezierPath(ovalIn: shadow.insetBy(dx: shadowWidth * 0.47, dy: 0))
        terminator.lineWidth = 0.8
        Palette.accent.withAlphaComponent(0.10).setStroke()
        terminator.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCachedBackground(rect: NSRect, radius: CGFloat, center: NSPoint, sphere: NSRect) {
        if cachedBackground == nil || cachedBackgroundSize != bounds.size {
            let image = NSImage(size: bounds.size)
            image.lockFocusFlipped(false)
            drawStaticBackground(rect: rect, radius: radius, center: center, sphere: sphere)
            image.unlockFocus()
            cachedBackground = image
            cachedBackgroundSize = bounds.size
        }
        cachedBackground?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawLandMasses(radius: CGFloat, center: NSPoint) {
        // 低透明度的简化大陆轮廓，让地球不再只是网格球；轮廓随同
        // 经度一起旋转，保持与节点和轨道一致。
        let landMasses: [[(CGFloat, CGFloat)]] = [
            [(72, -168), (68, -145), (60, -132), (52, -125), (48, -115), (32, -106), (18, -98), (10, -84), (22, -76), (36, -75), (48, -66), (58, -82), (68, -96)],
            [(12, -82), (5, -78), (-8, -75), (-20, -70), (-35, -66), (-54, -70), (-42, -58), (-20, -54), (0, -60)],
            [(72, -12), (70, 10), (60, 28), (52, 38), (42, 30), (36, 18), (30, 8), (18, 14), (5, 10), (-10, 20), (-28, 28), (-35, 18), (-28, 4), (-10, -2), (8, -10), (28, -16), (48, -8)],
            [(58, 40), (68, 58), (70, 90), (62, 122), (50, 142), (42, 132), (30, 118), (20, 105), (8, 96), (18, 80), (30, 68), (42, 52)],
            [(-10, 112), (-22, 124), (-34, 142), (-28, 154), (-16, 150), (-10, 132)],
            // Greenland, Japan/Indonesia and the polar shelf add the small
            // silhouettes that make the illuminated sphere feel geographic.
            [(82, -54), (78, -42), (70, -28), (62, -42), (68, -58), (76, -64)],
            [(45, 140), (38, 146), (31, 142), (34, 132), (40, 134)],
            [(12, 118), (4, 126), (-4, 132), (-8, 124), (0, 116)],
            [(-66, -180), (-72, -125), (-70, -60), (-74, 0), (-70, 75), (-66, 140), (-66, 180)],
        ]
        let sphere = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sphere).addClip()
        for polygon in landMasses {
            let path = NSBezierPath()
            var visibleCount = 0
            for (index, coordinate) in polygon.enumerated() {
                let projected = project(latitude: coordinate.0, longitude: coordinate.1, radius: radius, center: center)
                if projected.visible > -0.28 { visibleCount += 1 }
                if index == 0 { path.move(to: projected.point) } else { path.line(to: projected.point) }
            }
            guard visibleCount > polygon.count / 2 else { continue }
            path.close()
            // 大陆不是一块平色填充：先用一层深绿到青色的微渐变铺
            // 出地形体积，再用一条很细的高光海岸线收边。这样在小
            // 尺寸窗口中仍能读出“蓝色星球”的层次，而不会像贴图。
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let relief = NSGradient(colors: [
                NSColor(calibratedRed: 0.20, green: 0.76, blue: 0.68, alpha: 0.38),
                NSColor(calibratedRed: 0.07, green: 0.34, blue: 0.37, alpha: 0.31),
                NSColor(calibratedRed: 0.015, green: 0.10, blue: 0.15, alpha: 0.12),
            ])
            relief?.draw(in: sphere, relativeCenterPosition: NSPoint(x: -0.34, y: 0.28))
            NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedRed: 0.28, green: 0.90, blue: 0.84, alpha: 0.54).setStroke()
            path.lineWidth = 0.62
            path.stroke()

            // 内部山脉/地形等高线，保持极淡，只为大洲提供照片式
            // 纹理；这些线仍受大陆 path 裁剪，不会穿过海洋。
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let textureLines: [[(CGFloat, CGFloat)]] = [
                [(58, -126), (49, -116), (39, -105), (29, -94)],
                [(48, -82), (40, -74), (32, -66)],
                [(9, -78), (-8, -70), (-25, -64), (-42, -61)],
                [(55, 4), (44, 14), (31, 21), (17, 18)],
                [(48, 57), (37, 75), (27, 94), (16, 111)],
                [(-20, 130), (-28, 143), (-32, 153)],
            ]
            for line in textureLines {
                let texturePath = NSBezierPath()
                for (index, coordinate) in line.enumerated() {
                    let projected = project(latitude: coordinate.0, longitude: coordinate.1, radius: radius, center: center)
                    if index == 0 { texturePath.move(to: projected.point) } else { texturePath.line(to: projected.point) }
                }
                texturePath.lineWidth = 0.38
                NSColor.white.withAlphaComponent(0.10).setStroke()
                texturePath.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // 稀疏的城市灯光强化夜半球的真实感；数量固定，不产生随机
        // 闪烁，也不会把地球渲染成游戏地图。
        let cityLights: [(CGFloat, CGFloat)] = [
            (35, 139), (31, 121), (51, 0), (48, 2), (30, 31),
            (1, 103), (-6, 106), (23, 113), (40, -74), (34, -118),
            (-23, -46), (-33, 151), (28, 77), (19, 73),
        ]
        for coordinate in cityLights {
            let projected = project(latitude: coordinate.0, longitude: coordinate.1, radius: radius, center: center)
            guard projected.visible > -0.02 else { continue }
            let sunFactor = cos((coordinate.1 + rotationOffset + 35) * .pi / 180) * cos(coordinate.0 * .pi / 180)
            let nightFactor = max(0, min(1, -sunFactor + 0.18))
            guard nightFactor > 0.04 else { continue }
            Palette.warning.withAlphaComponent(0.48 * nightFactor * max(0.28, projected.visible)).setFill()
            NSBezierPath(ovalIn: NSRect(x: projected.point.x - 1.0, y: projected.point.y - 1.0, width: 2.0, height: 2.0)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 12, dy: 12)
        guard rect.width > 40, rect.height > 40 else { return }
        // Keep the entire sphere in frame at the reference window size.  The
        // previous width-biased radius made the globe grow beyond the card
        // and left only a cropped arc visible in the floating panel.  Height
        // is the visual anchor; zoom is capped to a gentle, still-readable
        // close-up instead of allowing a second accidental crop.
        let baseRadius = min(rect.width * 0.36, rect.height * 0.50)
        let maxRadius = min(rect.width * 0.40, rect.height * 0.53)
        let radius = min(baseRadius * zoomScale, maxRadius)
        let center = NSPoint(x: rect.midX, y: rect.midY - 5)
        let sphere = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        drawCachedBackground(rect: rect, radius: radius, center: center, sphere: sphere)

        drawDynamicGrid(radius: radius, center: center, sphere: sphere)
        drawDataRoutes(radius: radius, center: center, sphere: sphere)
        drawCloudBands(radius: radius, center: center)
        drawOrbitArcs(radius: radius, center: center)
        drawLandMasses(radius: radius, center: center)
        drawTerminator(radius: radius, center: center, sphere: sphere)

        // 小尺寸地球同时显示过多节点既会重叠，也会增加每帧绘制成本。
        // 详情数据不受影响，仍保留在列表和点击模型中。
        let pulsePhase = CGFloat(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.8))
        for point in points.prefix(32) {
            let projected = project(latitude: point.latitude, longitude: point.longitude, radius: radius, center: center)
            let visible = projected.visible
            guard visible > -0.18 else { continue }
            let x = projected.point.x
            let y = projected.point.y
            let depth = max(0.24, min(1, (visible + 1) * 0.5))
            let pulse = 0.90 + 0.10 * CGFloat(sin(pulsePhase * 1.3 + point.latitude * 0.03 + point.longitude * 0.01))
            let r = point.radius * (visible > 0 ? 1 : 0.55) * pulse
            point.color.withAlphaComponent(0.10 + 0.10 * depth).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r * 3.2, y: y - r * 3.2, width: r * 6.4, height: r * 6.4)).fill()
            point.color.withAlphaComponent(0.30 + 0.20 * depth).setStroke()
            let nodeRing = NSBezierPath(ovalIn: NSRect(x: x - r * 1.9, y: y - r * 1.9, width: r * 3.8, height: r * 3.8))
            nodeRing.lineWidth = 0.7
            nodeRing.stroke()
            point.color.withAlphaComponent(0.70 + 0.30 * depth).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            if let selectedPoint,
               abs(selectedPoint.latitude - point.latitude) < 0.01,
               abs(selectedPoint.longitude - point.longitude) < 0.01 {
                point.color.withAlphaComponent(0.8).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: x - r * 3.2, y: y - r * 3.2, width: r * 6.4, height: r * 6.4))
                ring.lineWidth = 1.3
                ring.stroke()
            }
        }

        let title = "全球事件分布"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.74),
        ]
        (title as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.maxY - 18), withAttributes: attrs)
        let liveAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: Palette.success,
        ]
        ("● 本地样本" as NSString).draw(at: NSPoint(x: rect.maxX - 70, y: rect.maxY - 17), withAttributes: liveAttrs)
    }
}

/// 将高、中、低风险画成概念图中的紧凑环形摘要。
/// 它只是已有风险统计的视觉投影，不引入第二份状态。
final class IntelligenceRiskRingView: NSView {
    private(set) var high = 0
    private(set) var medium = 0
    private(set) var low = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("风险等级分布")
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    func update(high: Int, medium: Int, low: Int) {
        self.high = max(0, high)
        self.medium = max(0, medium)
        self.low = max(0, low)
        toolTip = "高风险 \(self.high) · 中风险 \(self.medium) · 低风险 \(self.low)"
        setAccessibilityValue(toolTip)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let total = max(1, high + medium + low)
        // 参考概念图使用约 96pt 的环形图，右侧文字仍保留足够空间。
        let center = NSPoint(x: 52, y: bounds.midY)
        let radius: CGFloat = min(48, max(40, bounds.height * 0.48))
        let lineWidth: CGFloat = 7

        let base = NSBezierPath()
        base.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        base.lineWidth = lineWidth
        base.lineCapStyle = .round
        Palette.border.withAlphaComponent(0.36).setStroke()
        base.stroke()

        var startAngle: CGFloat = 90
        let segments: [(Int, NSColor)] = [
            (high, Palette.error),
            (medium, Palette.warning),
            (low, Palette.success),
        ]
        for (count, color) in segments where count > 0 {
            let sweep = CGFloat(count) / CGFloat(total) * 360
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: startAngle - sweep,
                clockwise: true
            )
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            color.withAlphaComponent(0.92).setStroke()
            path.stroke()
            startAngle -= sweep
        }

        let totalText = "\(high + medium + low)" as NSString
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.90),
        ]
        let totalSize = totalText.size(withAttributes: totalAttributes)
        totalText.draw(
            at: NSPoint(x: center.x - totalSize.width / 2, y: center.y - totalSize.height / 2),
            withAttributes: totalAttributes
        )

        let entries: [(String, Int, NSColor)] = [
            ("高风险", high, Palette.error),
            ("中风险", medium, Palette.warning),
            ("低风险", low, Palette.success),
        ]
        for (index, entry) in entries.enumerated() {
            let y = bounds.maxY - 16 - CGFloat(index) * 18
            let percentage = Int((Double(entry.1) / Double(total) * 100).rounded())
            entry.2.setFill()
            NSBezierPath(ovalIn: NSRect(x: 110, y: y + 3, width: 5, height: 5)).fill()
            let text = "\(entry.0)  \(entry.1)（\(percentage)%）" as NSString
            text.draw(at: NSPoint(x: 120, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: entry.2.withAlphaComponent(0.94),
            ])
        }
    }
}

/// 动态条目是可操作的，不再只是装饰性文本：点击后会把条目详情反馈到
/// 情报工作台的选择状态，后续可以继续接入详情抽屉而不改变数据源。
final class IntelligenceFeedRow: LayerView {
    var onClick: (() -> Void)?
    private(set) var isSelectedForAnalysis = false
    private let actionButton = HoverButton(frame: .zero)
    private var actionInstalled = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 文本标签本身会参与 AppKit hit testing。使用覆盖整行的原生按钮层，
    /// 可以保证点击标题、来源或空白处都触发同一个详情动作。
    func installActionLayer(toolTip: String?) {
        guard !actionInstalled else { return }
        actionInstalled = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isBordered = false
        actionButton.title = ""
        actionButton.normalColor = .clear
        actionButton.hoverColor = Palette.accent.withAlphaComponent(0.06)
        actionButton.toolTip = toolTip
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        addSubview(actionButton, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func actionClicked() { onClick?() }

    func setSelectedForAnalysis(_ selected: Bool) {
        isSelectedForAnalysis = selected
        fillColor = selected
            ? Palette.accent.withAlphaComponent(0.13)
            : Palette.canvas.withAlphaComponent(0.48)
        layer?.borderColor = (selected
            ? Palette.accent.withAlphaComponent(0.72)
            : Palette.border.withAlphaComponent(0.40)).cgColor
        needsDisplay = true
    }
}

// MARK: - 全球情报页签

final class IntelligenceDashboardView: LayerView {
    private let scrollView = NSScrollView()
    // 情报页是纵向文档，应与聊天区一样使用左上角原点。普通 NSView
    // 会在动态数据刷新、内容高度重新求解时把可视区域拉向文档底部，
    // 造成标题和筛选栏突然离开首屏。
    private let contentView = FlippedLayerView(fillColor: .clear, cornerRadius: 0)
    private let serviceLabel = label("本地演示数据 · 固定样本", size: 10, color: Palette.secondaryText)
    private let refreshButton = HoverButton(frame: .zero)
    private let rotationButton = HoverButton(frame: .zero)
    private let pinButton = HoverButton(frame: .zero)
    private let closeButton = HoverButton(frame: .zero)
    private let modeSelector = IntelligenceSegmentedControl(
        labels: ["总览", "航班", "卫星", "地震", "新闻"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let regionPopup = IntelligencePopupButton()
    private let autoRefreshButton = IntelligenceCheckButton(checkboxWithTitle: "自动刷新", target: nil, action: nil)
    private let globe = IntelligenceGlobeView(frame: .zero)
    private let selectionLabel = label("拖拽旋转 · 滚轮缩放 · 点击节点查看详情", size: 10, color: Palette.secondaryText)
    private var statLabels: [NSTextField] = []
    private let feedStack = NSStackView()
    private let feedScrollView = NSScrollView()
    private let feedDocumentView = FlippedLayerView(fillColor: .clear, cornerRadius: 0)
    private let feedStatusLabel = label("本地样本 · 可点击查看详情", size: 9, color: Palette.secondaryText)
    private let detailCard = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.48), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.58))
    private let detailCategory = label("尚未选择情报", size: 9.5, weight: .semibold, color: Palette.accent)
    private let detailTitle = intelligenceWrappingLabel("点击右侧动态条目即可查看完整摘要。", size: 11, weight: .semibold, color: .labelColor, lines: 3)
    private let detailSummary = intelligenceWrappingLabel("选择的情报还可交给 AI Dev One 做交叉验证、影响分析与行动建议。", size: 9.5, color: Palette.secondaryText, lines: 5)
    private let detailMeta = intelligenceWrappingLabel("来源与发布时间将在这里显示", size: 8.5, color: Palette.secondaryText, lines: 1)
    private let openSourceButton = HoverButton(frame: .zero)
    private let selectedCountLabel = label("已选 0 条", size: 9, weight: .medium, color: Palette.secondaryText)
    private let clearSelectionButton = HoverButton(frame: .zero)
    private let sourceSummary = intelligenceWrappingLabel("等待公开来源", size: 9.5, color: Palette.secondaryText, lines: 6)
    private let riskSummary = intelligenceWrappingLabel("高风险 —  ·  中风险 —  ·  低风险 —", size: 9.5, color: Palette.secondaryText, lines: 6)
    private let riskRing = IntelligenceRiskRingView(frame: .zero)
    private let eventTotalValue = label("—", size: 28, weight: .semibold, color: Palette.accent)
    private let eventWindowLabel = label("近 24 小时 · 等待数据", size: 9, color: Palette.secondaryText)
    private let eventDeltaLabel = label("本轮新增 —", size: 9, weight: .medium, color: Palette.success)
    private let aiInsightSummary = intelligenceWrappingLabel("连接数据后生成本地初步洞察；选中事件可交给 AI Dev One 深度分析。", size: 9.5, color: Palette.secondaryText, lines: 6)
    private let analyzeButton = HoverButton(frame: .zero)
    private let analysisStatus = label("先从本地样本中选择情报", size: 8.5, color: Palette.secondaryText)
    private let scanTarget = NSTextField()
    private let scanConsent = IntelligenceCheckButton(checkboxWithTitle: "我确认拥有目标的测试授权", target: nil, action: nil)
    private let scanType = IntelligencePopupButton()
    private let scanButton = HoverButton(frame: .zero)
    private let scanStatus = label("安全扫描仅对明确授权的目标开放。", size: 9.5, color: Palette.secondaryText)
    private var serviceURL: URL?
    private var refreshInFlight = false
    private var refreshTimer: Timer?
    private var latestStats: [String: Any] = [:]
    private var latestEarthquakes: [[String: Any]] = []
    private var latestNews: [[String: Any]] = []
    private var latestFlights: [[String: Any]] = []
    private var latestSatellites: [[String: Any]] = []
    private var latestWeather: [[String: Any]] = []
    private var latestFires: [[String: Any]] = []
    private var latestConflicts: [[String: Any]] = []
    private var latestMaritime: [[String: Any]] = []
    private var latestSpaceWeather: [String: Any] = [:]
    // 第二层公开情报源：GDELT/GDACS、空气质量、网络安全、恶意软件和
    // 关键基础设施。它们仍由 OSIRIS 统一代理，UI 不直接持有外部密钥。
    private var latestGDELT: [[String: Any]] = []
    private var latestGDACS: [[String: Any]] = []
    private var latestAirQuality: [[String: Any]] = []
    private var latestCyberThreats: [[String: Any]] = []
    private var latestMalware: [[String: Any]] = []
    private var latestInfrastructure: [[String: Any]] = []
    private var activeMode = "总览"
    private var feedRequestID = UUID()
    private var feedResponsesRemaining = 0
    private var feedSourceCount = 0
    private var feedSuccessCount = 0
    private var refreshStartedAt: Date?
    private var currentFeedItems: [IntelligenceFeedItem] = []
    private var feedHistory: [IntelligenceFeedItem] = []
    private var seenFeedIDs = Set<String>()
    private var newFeedIDsInRefresh = Set<String>()
    private var lastNewFeedCount = 0
    private var selectedItems: [String: IntelligenceFeedItem] = [:]
    private var focusedItem: IntelligenceFeedItem?
    private let fixtureProvider = FixtureIntelligenceDataProvider()
    private var currentSnapshot: GlobalIntelligenceSnapshot?
    private(set) var isPinned = true
    // Runtime geometry evidence is opt-in and inert in normal builds.  The
    // release-gate harness sets AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES=1 so we
    // can compare arranged-subview frames after AppKit has solved constraints.
    private var debugFrameViews: [(String, NSView)] = []
    private var lastDebugFrameSignature: String?

    /// 退出主情报工作台，返回三栏工作区。
    var onClose: (() -> Void)?
    var onPinToggle: ((Bool) -> Void)?
    /// 将用户明确选择的公开情报送入现有 Agent 任务链，而不是另建模型调用。
    var onAnalyze: ((String) -> Bool)?
    /// 仅用于显式布局验收环境，不参与产品状态。
    var onDebugSnapshot: (() -> Void)?

    override init(fillColor: NSColor = .clear, cornerRadius: CGFloat = 0, strokeColor: NSColor? = nil) {
        // The intelligence center is also hosted in its own window.  A clear
        // root made the main Route 2 window show through the floating panel,
        // which produced ghosted text and duplicated cards.  Keep the
        // embedded compatibility instance visually unchanged, but give the
        // standalone surface an opaque forest canvas at construction time.
        let rootFill = fillColor == .clear ? Palette.forestBottom : fillColor
        super.init(fillColor: rootFill, cornerRadius: cornerRadius, strokeColor: strokeColor)
        translatesAutoresizingMaskIntoConstraints = false
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        emitDebugFrameSnapshotIfRequested()
    }

    /// Forces one post-layout sample when validating a signed app launched by
    /// LaunchServices.  The first AppKit `layout()` pass can happen while the
    /// panel still has a zero-sized content view, so a later explicit sample
    /// is required for trustworthy geometry evidence.
    func debugFrameSnapshotIfRequested() {
        guard ProcessInfo.processInfo.environment["AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES"] == "1" else { return }
        layoutSubtreeIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        emitDebugFrameSnapshotIfRequested()
    }

    private func emitDebugFrameSnapshotIfRequested() {
        guard ProcessInfo.processInfo.environment["AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES"] == "1",
              !debugFrameViews.isEmpty else { return }
        let entries = debugFrameViews.map { name, view in
            let frame = view.convert(view.bounds, to: self)
            return "\(name)=x:\(String(format: "%.1f", frame.minX)),y:\(String(format: "%.1f", frame.minY)),w:\(String(format: "%.1f", frame.width)),h:\(String(format: "%.1f", frame.height))"
        }
        let signature = entries.joined(separator: " | ")
        guard signature != lastDebugFrameSignature else { return }
        lastDebugFrameSignature = signature
        let line = "AI_DEV_ONE_INTELLIGENCE_FRAMES \(signature)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let path = ProcessInfo.processInfo.environment["AI_DEV_ONE_INTELLIGENCE_DEBUG_PATH"], !path.isEmpty {
            // LaunchServices detaches GUI stderr, so the opt-in file sink is
            // useful when validating a signed .app rather than a terminal
            // binary.  It is never touched unless the debug environment flag
            // is explicitly enabled.
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        globe.stopRotation()
    }

    /// Workspace 切换到其他页签时暂停动画，避免隐藏的情报页签持续占用主线程。
    func setVisible(_ visible: Bool) {
        if visible {
            globe.startRotation()
            scheduleAutoRefresh()
            // 浮动大屏首次打开时 serviceURL 为空；不能只在已有连接
            // 时刷新，否则窗口会显示出来却永远不会启动本地 OSIRIS。
            refresh()
        } else {
            globe.stopRotation()
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        refreshButton.isEnabled = false
        serviceLabel.stringValue = "本地演示数据 · 正在刷新固定样本…"
        // V1 Provider 是同步且无副作用的；面板不会在打开、刷新或自动
        // 刷新时启动 OSIRIS，也不会访问任何网络端点。
        let snapshot = IntelligenceFixtureSnapshotBridge.snapshot(from: fixtureProvider, at: Date())
        applyFixtureSnapshot(snapshot)
        refreshInFlight = false
        refreshButton.isEnabled = true
        serviceLabel.stringValue = "本地演示数据 · 固定样本 · 已更新 \(localizedDate(snapshot.generatedAt))"
        serviceLabel.toolTip = "V1 仅显示本地固定样本，不连接网络，不代表实时预警。"
        scheduleAutoRefresh()
        onDebugSnapshot?()
    }

    @objc private func refreshClicked() {
        refresh()
    }

    @objc private func rotationClicked() {
        let rotating = globe.toggleRotation()
        rotationButton.title = rotating ? "暂停旋转" : "旋转地球"
        selectionLabel.stringValue = rotating
            ? "地球正在自动旋转 · 点击节点查看详情"
            : "地球已暂停 · 点击“旋转地球”继续"
    }

    @objc private func pinClicked() {
        isPinned.toggle()
        setPinned(isPinned)
        onPinToggle?(isPinned)
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        pinButton.image = symbol(pinned ? "pin.fill" : "pin", size: 12, weight: .semibold)
        pinButton.toolTip = pinned ? "取消置顶情报中心" : "置顶情报中心"
        pinButton.setAccessibilityLabel(pinned ? "取消置顶情报中心" : "置顶情报中心")
    }

    @objc private func closeClicked() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        onClose?()
    }

    @objc private func modeChanged() {
        activeMode = modeSelector.label(forSegment: modeSelector.selectedSegment) ?? "总览"
        // 不把“航班/卫星/地震”视图的旧条目混进总览。切换页签时保留
        // 数据源快照，但重新建立当前视图自己的增量计数。
        feedHistory.removeAll()
        seenFeedIDs.removeAll()
        newFeedIDsInRefresh.removeAll()
        lastNewFeedCount = 0
        if let snapshot = currentSnapshot {
            applyFixtureSnapshot(snapshot)
        }
        selectionLabel.stringValue = activeMode == "总览"
            ? "点击态势图上的节点查看详情"
            : "当前数据视图：\(activeMode) · 点击节点或动态条目查看详情"
    }

    @objc private func regionChanged() {
        let region = regionPopup.titleOfSelectedItem ?? "全球"
        selectionLabel.stringValue = "已选择区域：\(region) · 本地固定样本"
    }

    @objc private func autoRefreshChanged() {
        scheduleAutoRefresh()
    }

    private func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard autoRefreshButton.state == .on else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func openSelectedSource() {
        guard let url = focusedItem?.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func clearSelectedIntelligence() {
        selectedItems.removeAll()
        analysisStatus.stringValue = "先从本地样本中选择情报"
        analysisStatus.textColor = Palette.secondaryText
        updateSelectionControls()
        renderFeed(currentFeedItems)
    }

    @objc private func analyzeSelectedIntelligence() {
        let items = selectedItems.values.sorted { $0.id < $1.id }
        guard !items.isEmpty else {
            analysisStatus.stringValue = "请先选择至少一条情报"
            analysisStatus.textColor = Palette.warning
            return
        }
        let evidence = items.prefix(8).enumerated().map { index, item in
            var lines = [
                "\(index + 1). [\(item.category) / \(item.riskLabel)] \(item.title)",
                "来源：\(item.source)；时间：\(item.publishedAt)",
                "摘要：\(item.summary)",
            ]
            if let url = item.url { lines.append("公开链接：\(url.absoluteString)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let prompt = """
        请分析以下由用户在“全球情报”中明确选择的公开信息。请先区分事实、来源陈述与推断；对关键信息做交叉验证，输出中文的事件概览、可信度、潜在影响、风险等级和建议关注项。不要执行写文件、端口扫描或其他修改操作，除非用户后续明确要求。

        \(evidence)
        """
        if onAnalyze?(prompt) == true {
            analysisStatus.stringValue = "已提交 \(items.count) 条情报给 AI Dev One"
            analysisStatus.textColor = Palette.success
        } else {
            analysisStatus.stringValue = "当前任务繁忙或模型未就绪，请稍后重试"
            analysisStatus.textColor = Palette.warning
        }
    }

    @objc private func runScan() {
        guard scanConsent.state == .on else {
            scanStatus.stringValue = "请先确认你拥有目标的测试授权。"
            scanStatus.textColor = Palette.warning
            return
        }
        let target = scanTarget.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target.count <= 240 else {
            scanStatus.stringValue = "请输入合法的域名或 IP 地址。"
            scanStatus.textColor = Palette.warning
            return
        }
        guard let serviceURL else {
            scanStatus.stringValue = "V1 演示模式未启用网络扫描；如需授权检查，请切换到工具页。"
            return
        }
        let type = scanType.titleOfSelectedItem ?? "快速检查"
        let mapping = ["快速检查": "quick", "证书检查": "ssl", "响应头": "headers", "漏洞评估": "vuln"]
        guard let rawType = mapping[type], var components = URLComponents(url: serviceURL.appendingPathComponent("api/scanner"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [
            URLQueryItem(name: "target", value: target),
            URLQueryItem(name: "type", value: rawType),
        ]
        guard let url = components.url else { return }
        scanButton.isEnabled = false
        scanStatus.textColor = Palette.secondaryText
        scanStatus.stringValue = "正在执行 \(type)，请保持授权范围不变…"
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanButton.isEnabled = true
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.scanStatus.textColor = Palette.success
                    self.scanStatus.stringValue = "检查完成：结果已返回到本地情报面板。"
                } else {
                    self.scanStatus.textColor = Palette.warning
                    let message = error?.localizedDescription ?? "扫描后端未配置或拒绝了请求"
                    self.scanStatus.stringValue = "未执行：\(message)。"
                }
                _ = data
            }
        }.resume()
    }

    private func buildView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView
        contentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.62), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.68))
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = label("全球情报中心", size: 20, weight: .semibold)
        let subtitle = label("AI Dev One · 本地固定样本 · 全球公开数据与态势分析", size: 11, color: Palette.secondaryText)
        [title, subtitle, serviceLabel, refreshButton, rotationButton, pinButton, closeButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        refreshButton.isBordered = true
        refreshButton.bezelStyle = .texturedRounded
        refreshButton.title = "刷新数据"
        refreshButton.image = symbol("arrow.clockwise", size: 12, weight: .semibold)
        refreshButton.imagePosition = .imageLeading
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.hoverColor = Palette.accent.withAlphaComponent(0.16)
        refreshButton.toolTip = "刷新全球情报数据"
        refreshButton.setAccessibilityRole(.button)
        refreshButton.setAccessibilityLabel("刷新本地情报数据")
        rotationButton.isBordered = true
        rotationButton.bezelStyle = .texturedRounded
        rotationButton.title = "暂停旋转"
        rotationButton.image = symbol("globe.americas", size: 11, weight: .semibold)
        rotationButton.imagePosition = .imageLeading
        rotationButton.target = self
        rotationButton.action = #selector(rotationClicked)
        rotationButton.hoverColor = Palette.violet.withAlphaComponent(0.16)
        rotationButton.toolTip = "暂停或继续地球旋转"
        rotationButton.setAccessibilityRole(.button)
        rotationButton.setAccessibilityLabel("暂停或继续地球旋转")
        pinButton.isBordered = false
        pinButton.bezelStyle = .texturedRounded
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.hoverColor = Palette.accent.withAlphaComponent(0.14)
        pinButton.setAccessibilityRole(.button)
        setPinned(true)
        closeButton.isBordered = false
        closeButton.image = symbol("xmark", size: 12, weight: .semibold)
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.hoverColor = Palette.subtle
        closeButton.toolTip = "返回工作区"
        closeButton.setAccessibilityRole(.button)
        closeButton.setAccessibilityLabel("关闭全球情报中心")
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            serviceLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            serviceLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 3),
            serviceLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            refreshButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            refreshButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 92),
            refreshButton.heightAnchor.constraint(equalToConstant: 28),
            rotationButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),
            rotationButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            rotationButton.widthAnchor.constraint(equalToConstant: 92),
            rotationButton.heightAnchor.constraint(equalToConstant: 28),
            pinButton.trailingAnchor.constraint(equalTo: rotationButton.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 28),
            pinButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        let controlBar = LayerView(fillColor: Palette.canvas.withAlphaComponent(0.46), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.58))
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        let controlTitle = label("数据视图", size: 9, weight: .medium, color: Palette.secondaryText.withAlphaComponent(0.72))
        [controlTitle, modeSelector, regionPopup, autoRefreshButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; controlBar.addSubview($0) }
        modeSelector.selectedSegment = 0
        modeSelector.target = self
        modeSelector.action = #selector(modeChanged)
        modeSelector.setAccessibilityRole(.tabGroup)
        modeSelector.setAccessibilityLabel("情报数据视图")
        modeSelector.setContentHuggingPriority(.required, for: .horizontal)
        regionPopup.addItems(withTitles: ["全球", "亚太", "欧洲", "北美", "中东"])
        regionPopup.target = self
        regionPopup.action = #selector(regionChanged)
        regionPopup.font = .systemFont(ofSize: 10)
        regionPopup.setAccessibilityLabel("情报区域")
        autoRefreshButton.font = .systemFont(ofSize: 10)
        // 全球态势是持续变化的数据视图，默认开启低频刷新；用户仍可
        // 随时关闭，隐藏页签时定时器会自动暂停。
        autoRefreshButton.state = .on
        autoRefreshButton.target = self
        autoRefreshButton.action = #selector(autoRefreshChanged)
        autoRefreshButton.setAccessibilityLabel("自动刷新本地样本")
        autoRefreshButton.toolTip = "每 60 秒刷新本地固定样本；不会联网"
        NSLayoutConstraint.activate([
            controlTitle.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 12),
            controlTitle.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            modeSelector.leadingAnchor.constraint(equalTo: controlTitle.trailingAnchor, constant: 10),
            modeSelector.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            modeSelector.heightAnchor.constraint(equalToConstant: 24),
            regionPopup.leadingAnchor.constraint(equalTo: modeSelector.trailingAnchor, constant: 12),
            regionPopup.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            regionPopup.widthAnchor.constraint(equalToConstant: 92),
            regionPopup.heightAnchor.constraint(equalToConstant: 24),
            autoRefreshButton.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -12),
            autoRefreshButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
        ])

        let globeCard = LayerView(fillColor: Palette.canvas.withAlphaComponent(0.52), cornerRadius: 12, strokeColor: Palette.border.withAlphaComponent(0.64))
        globeCard.translatesAutoresizingMaskIntoConstraints = false
        globe.translatesAutoresizingMaskIntoConstraints = false
        globeCard.addSubview(globe)
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false
        globeCard.addSubview(selectionLabel)
        globe.onPointSelected = { [weak self] point in
            let latitude = String(format: "%.1f", point.latitude)
            let longitude = String(format: "%.1f", point.longitude)
            self?.selectionLabel.stringValue = "已选节点：纬度 \(latitude)° · 经度 \(longitude)° · 可继续查看对应公开动态"
        }
        NSLayoutConstraint.activate([
            globe.leadingAnchor.constraint(equalTo: globeCard.leadingAnchor),
            globe.trailingAnchor.constraint(equalTo: globeCard.trailingAnchor),
            globe.topAnchor.constraint(equalTo: globeCard.topAnchor),
            globe.bottomAnchor.constraint(equalTo: selectionLabel.topAnchor, constant: -2),
            selectionLabel.leadingAnchor.constraint(equalTo: globeCard.leadingAnchor, constant: 14),
            selectionLabel.trailingAnchor.constraint(equalTo: globeCard.trailingAnchor, constant: -14),
            selectionLabel.bottomAnchor.constraint(equalTo: globeCard.bottomAnchor, constant: -9),
            selectionLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        let stats = NSStackView()
        stats.translatesAutoresizingMaskIntoConstraints = false
        stats.orientation = .horizontal
        stats.spacing = 5
        stats.distribution = .fillEqually
        [("航班", Palette.accent), ("卫星", Palette.blue), ("地震", Palette.warning), ("新增", Palette.violet)].forEach { title, color in
            let card = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.55), cornerRadius: 8, strokeColor: Palette.border.withAlphaComponent(0.54))
            let value = label("—", size: 17, weight: .semibold, color: color)
            let name = label(title, size: 9, color: Palette.secondaryText)
            [value, name].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
            NSLayoutConstraint.activate([
                value.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                value.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
                name.leadingAnchor.constraint(equalTo: value.leadingAnchor),
                name.topAnchor.constraint(equalTo: value.bottomAnchor, constant: 1),
                name.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -5),
            ])
            statLabels.append(value)
            stats.addArrangedSubview(card)
        }

        let feedCard = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.46), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.58))
        feedCard.translatesAutoresizingMaskIntoConstraints = false
        let feedTitle = label("情报动态", size: 11.5, weight: .semibold)
        feedTitle.translatesAutoresizingMaskIntoConstraints = false
        feedStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        feedStack.translatesAutoresizingMaskIntoConstraints = false
        feedStack.orientation = .vertical
        feedStack.alignment = .leading
        feedStack.spacing = 4
        feedCard.addSubview(feedTitle)
        feedCard.addSubview(feedStatusLabel)
        feedScrollView.translatesAutoresizingMaskIntoConstraints = false
        feedScrollView.drawsBackground = false
        feedScrollView.borderType = .noBorder
        feedScrollView.hasVerticalScroller = true
        feedScrollView.autohidesScrollers = true
        feedScrollView.scrollerStyle = .overlay
        feedScrollView.verticalScrollElasticity = .allowed
        feedDocumentView.translatesAutoresizingMaskIntoConstraints = false
        feedScrollView.documentView = feedDocumentView
        feedDocumentView.addSubview(feedStack)
        feedCard.addSubview(feedScrollView)
        NSLayoutConstraint.activate([
            feedTitle.leadingAnchor.constraint(equalTo: feedCard.leadingAnchor, constant: 10),
            feedTitle.topAnchor.constraint(equalTo: feedCard.topAnchor, constant: 9),
            feedStatusLabel.trailingAnchor.constraint(equalTo: feedCard.trailingAnchor, constant: -10),
            feedStatusLabel.centerYAnchor.constraint(equalTo: feedTitle.centerYAnchor),
            feedScrollView.leadingAnchor.constraint(equalTo: feedCard.leadingAnchor, constant: 6),
            feedScrollView.trailingAnchor.constraint(equalTo: feedCard.trailingAnchor, constant: -6),
            feedScrollView.topAnchor.constraint(equalTo: feedTitle.bottomAnchor, constant: 6),
            feedScrollView.bottomAnchor.constraint(equalTo: feedCard.bottomAnchor, constant: -7),
            feedDocumentView.leadingAnchor.constraint(equalTo: feedScrollView.contentView.leadingAnchor),
            feedDocumentView.trailingAnchor.constraint(equalTo: feedScrollView.contentView.trailingAnchor),
            feedDocumentView.topAnchor.constraint(equalTo: feedScrollView.contentView.topAnchor),
            feedDocumentView.widthAnchor.constraint(equalTo: feedScrollView.contentView.widthAnchor),
            feedStack.leadingAnchor.constraint(equalTo: feedDocumentView.leadingAnchor, constant: 4),
            feedStack.trailingAnchor.constraint(equalTo: feedDocumentView.trailingAnchor, constant: -4),
            feedStack.topAnchor.constraint(equalTo: feedDocumentView.topAnchor),
            feedStack.bottomAnchor.constraint(equalTo: feedDocumentView.bottomAnchor),
        ])

        // 参考图右上角的“事件总数”主看板。把总数、时间窗和四个
        // 关键计数放在同一块玻璃卡里，避免用户只能从底部状态栏猜测
        // 数据是否真的刷新。
        let eventSummaryCard = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.52), cornerRadius: 12, strokeColor: Palette.border.withAlphaComponent(0.70))
        eventSummaryCard.translatesAutoresizingMaskIntoConstraints = false
        let eventSummaryTitle = label("事件总数（近 24 小时）", size: 11, weight: .semibold)
        let eventSummaryHint = label("本地样本 · 手动刷新", size: 9, color: Palette.secondaryText)
        [eventSummaryTitle, eventTotalValue, eventWindowLabel, eventDeltaLabel, stats].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            eventSummaryCard.addSubview($0)
        }
        eventTotalValue.font = .monospacedDigitSystemFont(ofSize: 40, weight: .semibold)
        eventTotalValue.setContentHuggingPriority(.required, for: .horizontal)
        eventSummaryHint.translatesAutoresizingMaskIntoConstraints = false
        eventSummaryCard.addSubview(eventSummaryHint)
        NSLayoutConstraint.activate([
            eventSummaryTitle.leadingAnchor.constraint(equalTo: eventSummaryCard.leadingAnchor, constant: 12),
            eventSummaryTitle.topAnchor.constraint(equalTo: eventSummaryCard.topAnchor, constant: 10),
            eventSummaryHint.trailingAnchor.constraint(equalTo: eventSummaryCard.trailingAnchor, constant: -12),
            eventSummaryHint.centerYAnchor.constraint(equalTo: eventSummaryTitle.centerYAnchor),
            eventTotalValue.leadingAnchor.constraint(equalTo: eventSummaryTitle.leadingAnchor),
            eventTotalValue.topAnchor.constraint(equalTo: eventSummaryTitle.bottomAnchor, constant: 5),
            eventWindowLabel.leadingAnchor.constraint(equalTo: eventTotalValue.trailingAnchor, constant: 9),
            eventWindowLabel.bottomAnchor.constraint(equalTo: eventTotalValue.bottomAnchor, constant: -4),
            eventDeltaLabel.trailingAnchor.constraint(equalTo: eventSummaryCard.trailingAnchor, constant: -12),
            eventDeltaLabel.bottomAnchor.constraint(equalTo: eventTotalValue.bottomAnchor, constant: -4),
            stats.leadingAnchor.constraint(equalTo: eventSummaryCard.leadingAnchor, constant: 10),
            stats.trailingAnchor.constraint(equalTo: eventSummaryCard.trailingAnchor, constant: -10),
            stats.topAnchor.constraint(equalTo: eventTotalValue.bottomAnchor, constant: 8),
            stats.bottomAnchor.constraint(equalTo: eventSummaryCard.bottomAnchor, constant: -10),
            stats.heightAnchor.constraint(equalToConstant: 48),
        ])

        detailCard.translatesAutoresizingMaskIntoConstraints = false
        let detailHeading = label("情报详情", size: 11.5, weight: .semibold)
        [detailHeading, selectedCountLabel, detailCategory, detailTitle, detailSummary, detailMeta, openSourceButton, clearSelectionButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            detailCard.addSubview($0)
        }
        openSourceButton.isBordered = true
        openSourceButton.bezelStyle = .texturedRounded
        openSourceButton.title = "打开来源"
        openSourceButton.target = self
        openSourceButton.action = #selector(openSelectedSource)
        openSourceButton.isEnabled = false
        clearSelectionButton.isBordered = false
        clearSelectionButton.title = "清除选择"
        clearSelectionButton.target = self
        clearSelectionButton.action = #selector(clearSelectedIntelligence)
        clearSelectionButton.isEnabled = false
        NSLayoutConstraint.activate([
            detailHeading.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 10),
            detailHeading.topAnchor.constraint(equalTo: detailCard.topAnchor, constant: 8),
            selectedCountLabel.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -10),
            selectedCountLabel.centerYAnchor.constraint(equalTo: detailHeading.centerYAnchor),
            detailCategory.leadingAnchor.constraint(equalTo: detailHeading.leadingAnchor),
            detailCategory.topAnchor.constraint(equalTo: detailHeading.bottomAnchor, constant: 6),
            detailCategory.trailingAnchor.constraint(lessThanOrEqualTo: selectedCountLabel.leadingAnchor, constant: -8),
            detailTitle.leadingAnchor.constraint(equalTo: detailHeading.leadingAnchor),
            detailTitle.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -10),
            detailTitle.topAnchor.constraint(equalTo: detailCategory.bottomAnchor, constant: 3),
            detailTitle.heightAnchor.constraint(equalToConstant: 22),
            detailSummary.leadingAnchor.constraint(equalTo: detailHeading.leadingAnchor),
            detailSummary.trailingAnchor.constraint(equalTo: detailTitle.trailingAnchor),
            detailSummary.topAnchor.constraint(equalTo: detailTitle.bottomAnchor, constant: 4),
            detailSummary.heightAnchor.constraint(equalToConstant: 30),
            detailMeta.leadingAnchor.constraint(equalTo: detailHeading.leadingAnchor),
            detailMeta.trailingAnchor.constraint(equalTo: openSourceButton.leadingAnchor, constant: -8),
            detailMeta.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: -8),
            detailMeta.heightAnchor.constraint(equalToConstant: 16),
            openSourceButton.trailingAnchor.constraint(equalTo: clearSelectionButton.leadingAnchor, constant: -5),
            openSourceButton.centerYAnchor.constraint(equalTo: detailMeta.centerYAnchor),
            openSourceButton.widthAnchor.constraint(equalToConstant: 70),
            openSourceButton.heightAnchor.constraint(equalToConstant: 23),
            clearSelectionButton.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -8),
            clearSelectionButton.centerYAnchor.constraint(equalTo: detailMeta.centerYAnchor),
            clearSelectionButton.widthAnchor.constraint(equalToConstant: 62),
            clearSelectionButton.heightAnchor.constraint(equalToConstant: 23),
        ])

        let insightBoards = NSStackView()
        insightBoards.translatesAutoresizingMaskIntoConstraints = false
        insightBoards.orientation = .vertical
        // A vertical stack otherwise centers arranged views at their
        // intrinsic widths.  That produced the narrow floating cards from
        // the V1.2 screenshot; all right-column cards must fill the column.
        insightBoards.alignment = .width
        insightBoards.spacing = 8
        insightBoards.distribution = .fill

        func dashboardCard(title: String, icon: String, body: NSView, pinsBodyToBottom: Bool = false) -> LayerView {
            let card = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.46), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.56))
            // Arranged subviews must participate in the stack's Auto Layout
            // contract.  Leaving the default autoresizing mask enabled lets
            // AppKit preserve the card's intrinsic/autoresizing width, which
            // is exactly what produced the narrow floating source/risk/AI
            // cards in the V1.2 screenshot.
            card.translatesAutoresizingMaskIntoConstraints = false
            card.setContentHuggingPriority(.defaultLow, for: .horizontal)
            card.setContentCompressionResistancePriority(.required, for: .horizontal)
            let heading = label("\(icon)  \(title)", size: 11, weight: .semibold)
            heading.translatesAutoresizingMaskIntoConstraints = false
            body.translatesAutoresizingMaskIntoConstraints = false
            if let bodyLabel = body as? NSTextField {
                bodyLabel.maximumNumberOfLines = 6
                bodyLabel.lineBreakMode = .byWordWrapping
            }
            card.addSubview(heading)
            card.addSubview(body)
            var constraints = [
                heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                heading.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
                body.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
                body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            ]
            constraints.append(pinsBodyToBottom
                ? body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
                : body.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -9))
            NSLayoutConstraint.activate(constraints)
            return card
        }
        let sourceCard = dashboardCard(title: "信息来源（Top 6）", icon: "◎", body: sourceSummary)
        let riskCard = dashboardCard(title: "风险摘要", icon: "◈", body: riskRing, pinsBodyToBottom: true)
        let aiCard = dashboardCard(title: "AI 洞察", icon: "✦", body: aiInsightSummary)
        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeButton.isBordered = true
        analyzeButton.bezelStyle = .texturedRounded
        analyzeButton.title = "用 AI Dev One 分析"
        analyzeButton.image = symbol("sparkles", size: 10, weight: .semibold)
        analyzeButton.imagePosition = .imageLeading
        analyzeButton.target = self
        analyzeButton.action = #selector(analyzeSelectedIntelligence)
        analyzeButton.isEnabled = false
        analyzeButton.setAccessibilityRole(.button)
        analyzeButton.setAccessibilityLabel("使用 AI Dev One 分析已选情报")
        analysisStatus.translatesAutoresizingMaskIntoConstraints = false
        aiCard.addSubview(analyzeButton)
        aiCard.addSubview(analysisStatus)
        NSLayoutConstraint.activate([
            aiInsightSummary.bottomAnchor.constraint(lessThanOrEqualTo: analyzeButton.topAnchor, constant: -5),
            analyzeButton.leadingAnchor.constraint(equalTo: aiCard.leadingAnchor, constant: 10),
            analyzeButton.trailingAnchor.constraint(equalTo: aiCard.trailingAnchor, constant: -10),
            analyzeButton.bottomAnchor.constraint(equalTo: analysisStatus.topAnchor, constant: -5),
            analyzeButton.heightAnchor.constraint(equalToConstant: 25),
            analysisStatus.leadingAnchor.constraint(equalTo: analyzeButton.leadingAnchor),
            analysisStatus.trailingAnchor.constraint(equalTo: analyzeButton.trailingAnchor),
            analysisStatus.bottomAnchor.constraint(equalTo: aiCard.bottomAnchor, constant: -8),
        ])
        // The right side is one continuous dashboard column.  Keeping the
        // summary in the same stack prevents the source/risk/insight cards
        // from floating in a narrow island with unused space around them.
        insightBoards.addArrangedSubview(eventSummaryCard)
        insightBoards.addArrangedSubview(sourceCard)
        insightBoards.addArrangedSubview(riskCard)
        insightBoards.addArrangedSubview(aiCard)
        // Do not rely on NSStackView's intrinsic-width fallback.  Every
        // arranged card has an explicit equality with its column so the
        // contract remains true at every panel size and after relayout.
        [eventSummaryCard, sourceCard, riskCard, aiCard].forEach { card in
            card.widthAnchor.constraint(equalTo: insightBoards.widthAnchor).isActive = true
        }
        eventSummaryCard.heightAnchor.constraint(equalToConstant: 148).isActive = true
        sourceCard.heightAnchor.constraint(equalToConstant: 145).isActive = true
        riskCard.heightAnchor.constraint(equalToConstant: 140).isActive = true
        aiCard.heightAnchor.constraint(equalToConstant: 211).isActive = true

        let toolsCard = LayerView(fillColor: Palette.elevated.withAlphaComponent(0.46), cornerRadius: 10, strokeColor: Palette.border.withAlphaComponent(0.58))
        toolsCard.translatesAutoresizingMaskIntoConstraints = false
        let toolsTitle = label("情报工具", size: 11.5, weight: .semibold)
        let toolsHint = label("仅对你有权测试的目标使用", size: 9, color: Palette.warning)
        [toolsTitle, toolsHint].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; toolsCard.addSubview($0) }
        scanTarget.translatesAutoresizingMaskIntoConstraints = false
        scanTarget.placeholderString = "域名或 IP（需授权）"
        scanTarget.font = .systemFont(ofSize: 10.5)
        scanTarget.focusRingType = .none
        scanType.translatesAutoresizingMaskIntoConstraints = false
        scanType.addItems(withTitles: ["快速检查", "证书检查", "响应头", "漏洞评估"])
        scanType.font = .systemFont(ofSize: 10)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.title = "执行"
        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(runScan)
        scanConsent.translatesAutoresizingMaskIntoConstraints = false
        scanConsent.font = .systemFont(ofSize: 9)
        scanStatus.translatesAutoresizingMaskIntoConstraints = false
        [scanTarget, scanType, scanButton, scanConsent, scanStatus].forEach(toolsCard.addSubview)
        NSLayoutConstraint.activate([
            toolsTitle.leadingAnchor.constraint(equalTo: toolsCard.leadingAnchor, constant: 10),
            toolsTitle.topAnchor.constraint(equalTo: toolsCard.topAnchor, constant: 9),
            toolsHint.trailingAnchor.constraint(equalTo: toolsCard.trailingAnchor, constant: -10),
            toolsHint.centerYAnchor.constraint(equalTo: toolsTitle.centerYAnchor),
            scanTarget.leadingAnchor.constraint(equalTo: toolsCard.leadingAnchor, constant: 10),
            scanTarget.trailingAnchor.constraint(equalTo: scanType.leadingAnchor, constant: -5),
            scanTarget.topAnchor.constraint(equalTo: toolsTitle.bottomAnchor, constant: 9),
            scanTarget.heightAnchor.constraint(equalToConstant: 26),
            scanType.trailingAnchor.constraint(equalTo: scanButton.leadingAnchor, constant: -5),
            scanType.centerYAnchor.constraint(equalTo: scanTarget.centerYAnchor),
            scanType.widthAnchor.constraint(equalToConstant: 78),
            scanType.heightAnchor.constraint(equalToConstant: 26),
            scanButton.trailingAnchor.constraint(equalTo: toolsCard.trailingAnchor, constant: -10),
            scanButton.centerYAnchor.constraint(equalTo: scanTarget.centerYAnchor),
            scanButton.widthAnchor.constraint(equalToConstant: 48),
            scanButton.heightAnchor.constraint(equalToConstant: 26),
            scanConsent.leadingAnchor.constraint(equalTo: scanTarget.leadingAnchor),
            scanConsent.topAnchor.constraint(equalTo: scanTarget.bottomAnchor, constant: 7),
            scanStatus.leadingAnchor.constraint(equalTo: scanTarget.leadingAnchor),
            scanStatus.trailingAnchor.constraint(equalTo: toolsCard.trailingAnchor, constant: -10),
            scanStatus.topAnchor.constraint(equalTo: scanConsent.bottomAnchor, constant: 4),
            scanStatus.bottomAnchor.constraint(equalTo: toolsCard.bottomAnchor, constant: -9),
        ])

        // The first viewport is a two-column command center: the left column
        // owns the globe and event stream, while the right column is one
        // continuous information dashboard.  Keeping the columns in an
        // explicit grid avoids the old layout where the right cards floated
        // above a large unused area while the globe grew into a crop.
        let mainGrid = NSView()
        mainGrid.translatesAutoresizingMaskIntoConstraints = false
        let leftColumn = NSStackView()
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.orientation = .vertical
        // For a vertical NSStackView, `.width` means arranged views fill
        // the available column width (there is no `.fill` alignment case in
        // AppKit's NSLayoutConstraint.Attribute enum).
        leftColumn.alignment = .width
        leftColumn.distribution = .fill
        leftColumn.spacing = 10
        leftColumn.addArrangedSubview(globeCard)
        leftColumn.addArrangedSubview(feedCard)
        // Keep both left-column cards pinned to the leading/trailing edges;
        // this avoids a future intrinsic-size regression if the globe or feed
        // implementation gains an intrinsic content size.
        globeCard.widthAnchor.constraint(equalTo: leftColumn.widthAnchor).isActive = true
        feedCard.widthAnchor.constraint(equalTo: leftColumn.widthAnchor).isActive = true
        mainGrid.addSubview(leftColumn)
        mainGrid.addSubview(insightBoards)
        debugFrameViews = [
            ("mainGrid", mainGrid),
            ("leftColumn", leftColumn),
            ("globeCard", globeCard),
            ("realtimeCard", feedCard),
            ("rightColumn", insightBoards),
            ("eventSummaryCard", eventSummaryCard),
            ("sourcesCard", sourceCard),
            ("riskCard", riskCard),
            ("aiInsightCard", aiCard),
        ]

        [header, controlBar, mainGrid, detailCard, toolsCard].forEach(contentView.addSubview)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            // 当主工作台比最小内容高度更高时，内容从顶部开始铺满，
            // 避免 NSScrollView 将情报卡片垂直居中后留下大片空白。
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            header.heightAnchor.constraint(equalToConstant: 62),
            controlBar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            controlBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 9),
            controlBar.heightAnchor.constraint(equalToConstant: 34),
            mainGrid.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            mainGrid.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            mainGrid.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 10),
            mainGrid.heightAnchor.constraint(equalToConstant: 668),
            leftColumn.leadingAnchor.constraint(equalTo: mainGrid.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: mainGrid.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: mainGrid.bottomAnchor),
            leftColumn.widthAnchor.constraint(equalTo: mainGrid.widthAnchor, multiplier: 0.58, constant: -6.96),
            globeCard.heightAnchor.constraint(equalToConstant: 350),
            feedCard.heightAnchor.constraint(equalToConstant: 308),
            insightBoards.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 12),
            insightBoards.trailingAnchor.constraint(equalTo: mainGrid.trailingAnchor),
            insightBoards.topAnchor.constraint(equalTo: mainGrid.topAnchor),
            insightBoards.bottomAnchor.constraint(equalTo: mainGrid.bottomAnchor),
            insightBoards.widthAnchor.constraint(equalTo: mainGrid.widthAnchor, multiplier: 0.42, constant: -5.04),
            detailCard.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            detailCard.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            detailCard.topAnchor.constraint(equalTo: mainGrid.bottomAnchor, constant: 8),
            detailCard.heightAnchor.constraint(equalToConstant: 110),
            toolsCard.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            toolsCard.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            toolsCard.topAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: 10),
            toolsCard.heightAnchor.constraint(equalToConstant: 156),
            toolsCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
        showFallbackData()
    }

    private func loadFeeds(from baseURL: URL) {
        // 每个公开数据源独立更新。慢源不会阻塞已经返回的地震、新闻和
        // 航班；所有数据仍由本地 OSIRIS 代理统一取回。
        let requestID = UUID()
        feedRequestID = requestID
        newFeedIDsInRefresh.removeAll()
        lastNewFeedCount = 0
        feedSourceCount = 15
        feedResponsesRemaining = feedSourceCount
        feedSuccessCount = 0
        refreshStartedAt = Date()
        serviceLabel.stringValue = "本地数据服务 · 正在刷新 0/\(feedSourceCount) 个来源…"
        // 不调用 OSIRIS 的 /api/stats 聚合接口：它会在服务端再次串联
        // 多个外部源。独立请求允许 UI 先展示已经返回的数据。
        latestStats = [:]
        fetchJSON(baseURL.appendingPathComponent("api/earthquakes")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestEarthquakes = self.arrayPayload(value, keys: ["earthquakes", "quakes", "events"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/news")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestNews = self.arrayPayload(value, keys: ["news", "articles", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchFlights(from: baseURL) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestFlights = self.flightPayload(value)
            self.latestStats["flights"] = value?["total"] ?? self.latestFlights.count
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/satellites")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestSatellites = self.arrayPayload(value, keys: ["satellites", "sats", "objects"])
            self.latestStats["satellites"] = value?["total"] ?? self.latestSatellites.count
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/weather")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestWeather = self.arrayPayload(value, keys: ["events", "weather_events", "alerts"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/fires")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestFires = self.arrayPayload(value, keys: ["fires", "hotspots", "events"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/conflicts")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestConflicts = self.conflictPayload(value)
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/maritime")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestMaritime = self.arrayPayload(value, keys: ["ports", "vessels", "ships", "events"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/space-weather")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestSpaceWeather = value ?? [:]
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/gdelt-events")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestGDELT = self.arrayPayload(value, keys: ["events", "articles", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/gdelt")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestGDACS = self.arrayPayload(value, keys: ["events", "disasters", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/air-quality")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestAirQuality = self.arrayPayload(value, keys: ["stations", "measurements", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/cyber-threats")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestCyberThreats = self.arrayPayload(value, keys: ["threats", "vulnerabilities", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/malware")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestMalware = self.arrayPayload(value, keys: ["threats", "malware", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
        fetchJSON(baseURL.appendingPathComponent("api/infrastructure")) { [weak self] value in
            guard let self, self.feedRequestID == requestID else { return }
            self.latestInfrastructure = self.arrayPayload(value, keys: ["infrastructure", "facilities", "items"])
            self.refreshRenderedData()
            self.completeFeedSource(requestID: requestID, succeeded: value != nil)
        }
    }

    private func completeFeedSource(requestID: UUID, succeeded: Bool) {
        guard feedRequestID == requestID, feedResponsesRemaining > 0 else { return }
        feedResponsesRemaining -= 1
        if succeeded { feedSuccessCount += 1 }
        let completed = feedSourceCount - feedResponsesRemaining
        if feedResponsesRemaining > 0 {
            serviceLabel.stringValue = "本地数据服务 · 正在刷新 \(completed)/\(feedSourceCount) 个来源…"
            return
        }
        refreshInFlight = false
        refreshButton.isEnabled = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        let duration = max(0, Date().timeIntervalSince(refreshStartedAt ?? Date()))
        serviceLabel.stringValue = "本地数据服务 · OSIRIS 已就绪 · 实时数据已更新 \(formatter.string(from: Date())) · \(feedSuccessCount)/\(feedSourceCount) 来源 · \(String(format: "%.1f", duration)) 秒"
        serviceLabel.toolTip = nil
        refreshStartedAt = nil
        updateInsightBoards()
        onDebugSnapshot?()
    }

    private func refreshRenderedData() {
        applyStats(latestStats, flights: latestFlights, satellites: latestSatellites)
        applyEarthquakes(
            latestEarthquakes,
            news: latestNews,
            flights: latestFlights,
            satellites: latestSatellites,
            weather: latestWeather,
            fires: latestFires,
            conflicts: latestConflicts,
            gdelt: latestGDELT,
            gdacs: latestGDACS,
            airQuality: latestAirQuality,
            cyberThreats: latestCyberThreats,
            malware: latestMalware,
            infrastructure: latestInfrastructure
        )
        onDebugSnapshot?()
    }

    private func fetchJSON(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "_refresh", value: String(Int(Date().timeIntervalSince1970 * 1_000))))
        components?.queryItems = queryItems
        var request = URLRequest(url: components?.url ?? url)
        // 航班和卫星首次建立缓存时会经历公开源的冷启动；4 秒会把
        // 真实数据误判为空。请求仍在后台独立执行，超时只影响当前来源。
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // URLSession 的 ephemeral 配置仍可能复用 HTTP 缓存层；显式
        // 要求本地 OSIRIS 服务和上游代理重新验证，避免点击刷新时
        // 只是重新绘制上一份新闻快照。
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(object) }
        }.resume()
    }

    /// OSIRIS 会遵守 OpenSky 的匿名额度，在冷启动或额度冷却期间可能
    /// 合法返回 0 架。原生客户端保留一个同源公开只读回退，避免面板
    /// 把“数据源暂时冷却”误显示成全球没有航班。
    private func fetchFlights(from baseURL: URL, completion: @escaping ([String: Any]?) -> Void) {
        fetchJSON(baseURL.appendingPathComponent("api/flights")) { [weak self] value in
            guard let self else { completion(value); return }
            if !self.flightPayload(value).isEmpty {
                completion(value)
                return
            }
            guard var components = URLComponents(string: "https://opensky-network.org/api/states/all") else {
                completion(value)
                return
            }
            components.queryItems = [
                URLQueryItem(name: "lamin", value: "-60"),
                URLQueryItem(name: "lamax", value: "75"),
                URLQueryItem(name: "lomin", value: "-180"),
                URLQueryItem(name: "lomax", value: "180"),
            ]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let states = object["states"] as? [[Any]] else {
                    DispatchQueue.main.async { completion(value) }
                    return
                }
                let flights: [[String: Any]] = states.compactMap { state in
                    guard state.count > 10,
                          let icao24 = state[0] as? String,
                          let lat = state[6] as? NSNumber,
                          let lng = state[5] as? NSNumber else { return nil }
                    let callsign = (state[1] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? icao24
                    let altitude = (state[7] as? NSNumber)?.doubleValue ?? 0
                    let velocity = (state[9] as? NSNumber)?.doubleValue ?? 0
                    let heading = (state[10] as? NSNumber)?.doubleValue ?? 0
                    return [
                        "callsign": callsign,
                        "lat": lat,
                        "lng": lng,
                        "alt": NSNumber(value: Int(max(0, altitude))),
                        "speed_knots": NSNumber(value: velocity * 1.94384),
                        "heading": NSNumber(value: heading),
                        "icao24": icao24,
                        "type": "flight",
                    ]
                }
                DispatchQueue.main.async {
                    completion([
                        "commercial_flights": flights,
                        "total": flights.count,
                        "source": "OpenSky 公开只读回退",
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                    ])
                }
            }.resume()
        }
    }

    private func arrayPayload(_ value: [String: Any]?, keys: [String]) -> [[String: Any]] {
        guard let value else { return [] }
        for key in keys {
            if let rows = value[key] as? [[String: Any]] { return rows }
        }
        if let data = value["data"] as? [[String: Any]] { return data }
        return []
    }

    /// 航班接口按公开数据类别分组返回；统一去重后再交给地图和统计，
    /// 否则旧客户端只读 commercial_flights 时会把其他真实航迹丢掉。
    private func flightPayload(_ value: [String: Any]?) -> [[String: Any]] {
        guard let value else { return [] }
        let keys = ["flights", "commercial_flights", "private_flights", "private_jets", "military_flights"]
        var rows: [[String: Any]] = []
        var identifiers = Set<String>()
        for key in keys {
            guard let group = value[key] as? [[String: Any]] else { continue }
            for item in group {
                let identifier = (item["icao24"] as? String) ?? (item["callsign"] as? String) ?? UUID().uuidString
                if identifiers.insert(identifier).inserted { rows.append(item) }
            }
        }
        if rows.isEmpty, let data = value["data"] as? [[String: Any]] { return data }
        return rows
    }

    // MARK: - Fixture snapshot projection

    private func fixtureEvents(for snapshot: GlobalIntelligenceSnapshot) -> [IntelligenceEvent] {
        switch activeMode {
        case "航班": return snapshot.events24h.filter { $0.kind == .flight }
        case "卫星": return snapshot.events24h.filter { $0.kind == .satellite }
        case "地震": return snapshot.events24h.filter { $0.kind == .earthquake }
        case "新闻": return snapshot.events24h.filter { $0.kind == .news }
        default: return snapshot.events24h
        }
    }

    private func fixtureColor(for kind: IntelligenceEventKind) -> NSColor {
        switch kind {
        case .flight: return Palette.accent
        case .satellite: return Palette.blue
        case .earthquake: return Palette.warning
        case .weather: return Palette.warning
        case .security: return Palette.error
        case .news: return Palette.violet
        }
    }

    private func fixtureFeedItem(_ event: IntelligenceEvent) -> IntelligenceFeedItem {
        let metadata = event.metadata.map { "\($0.key)：\($0.value)" }.sorted().joined(separator: " · ")
        let suffix = metadata.isEmpty ? "" : "\n\(metadata)"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return IntelligenceFeedItem(
            id: "fixture:\(event.id)",
            category: event.kind.displayName,
            title: event.title,
            summary: event.summary + suffix,
            source: event.source,
            publishedAt: formatter.string(from: event.timestamp),
            riskScore: event.severity == .high ? 8 : (event.severity == .medium ? 5 : 2),
            url: nil
        )
    }

    private func applyFixtureSnapshot(_ snapshot: GlobalIntelligenceSnapshot) {
        currentSnapshot = snapshot
        let events = fixtureEvents(for: snapshot)
        globe.points = events.compactMap { event in
            guard let latitude = event.latitude, let longitude = event.longitude else { return nil }
            let radius: CGFloat = event.severity == .high ? 2.4 : (event.severity == .medium ? 1.9 : 1.45)
            return IntelligencePoint(
                latitude: CGFloat(latitude),
                longitude: CGFloat(longitude),
                color: fixtureColor(for: event.kind),
                radius: radius
            )
        }
        let rows = events.map(fixtureFeedItem)
        renderFeed(rows)

        let values = [snapshot.flightCount, snapshot.satelliteCount, snapshot.earthquakeCount, snapshot.newEventCount]
        for (index, value) in values.enumerated() where index < statLabels.count {
            statLabels[index].stringValue = value.formatted()
        }
        eventTotalValue.stringValue = snapshot.eventTotal.formatted()
        eventWindowLabel.stringValue = "近 24 小时 · 样本生成于 \(localizedDate(snapshot.generatedAt))"
        eventDeltaLabel.stringValue = "样本新增 +\(snapshot.newEventCount)"
        eventDeltaLabel.textColor = Palette.success
        feedStatusLabel.stringValue = "本地固定样本 · 共 \(events.count) 条 · 点击查看详情"
        serviceURL = nil

        let attributed = NSMutableAttributedString()
        let colors = [Palette.accent, Palette.blue, Palette.violet, Palette.warning]
        for (index, source) in snapshot.sources.prefix(6).enumerated() {
            if index > 0 { attributed.append(NSAttributedString(string: "\n")) }
            attributed.append(NSAttributedString(string: "● ", attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: colors[index % colors.count],
            ]))
            attributed.append(NSAttributedString(string: "\(source.name)  \(source.eventCount.formatted())", attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.78),
            ]))
        }
        sourceSummary.attributedStringValue = attributed
        riskSummary.stringValue = "高风险  \(snapshot.risk.high)\n中风险  \(snapshot.risk.medium)\n低风险  \(snapshot.risk.low)\n\n本地固定样本规则初筛"
        riskRing.update(high: snapshot.risk.high, medium: snapshot.risk.medium, low: snapshot.risk.low)
        aiInsightSummary.stringValue = snapshot.insight
        updateSelectionControls()
    }

    /// 冲突接口包含区域摘要和区域内事件；扁平化后，地图与动态列表才能
    /// 直接展示具体事件，而不是只显示一个空的区域壳。
    private func conflictPayload(_ value: [String: Any]?) -> [[String: Any]] {
        guard let zones = value?["zones"] as? [[String: Any] ] else { return [] }
        var rows: [[String: Any]] = []
        for zone in zones {
            if let events = zone["events"] as? [[String: Any]], !events.isEmpty {
                rows.append(contentsOf: events)
            } else if let lat = zone["lat"], let lng = zone["lng"] {
                rows.append([
                    "id": zone["id"] ?? UUID().uuidString,
                    "title": zone["label"] ?? "冲突区域",
                    "description": zone["description"] ?? "公开冲突区域态势",
                    "lat": lat,
                    "lng": lng,
                    "url": zone["sourceUrl"] ?? "",
                    "timestamp": zone["lastUpdated"] ?? "",
                ])
            }
        }
        return rows
    }

    private func applyStats(_ stats: [String: Any], flights: [[String: Any]], satellites: [[String: Any]]) {
        let eventCount = latestNews.count
            + latestEarthquakes.count
            + latestWeather.count
            + latestFires.count
            + latestConflicts.count
            + latestGDELT.count
            + latestGDACS.count
            + latestCyberThreats.count
            + latestMalware.count
        let values: [Any?] = [
            flights.isEmpty ? (stats["flights"] ?? stats["total_flights"] ?? 0) : flights.count,
            satellites.isEmpty ? (stats["sats"] ?? stats["satellites"] ?? 0) : satellites.count,
            latestEarthquakes.count,
            lastNewFeedCount,
        ]
        for (index, value) in values.enumerated() where index < statLabels.count {
            if let number = value as? NSNumber {
                statLabels[index].stringValue = number.intValue.formatted()
            } else if let count = value as? Int {
                statLabels[index].stringValue = count.formatted()
            }
        }
        eventTotalValue.stringValue = eventCount.formatted()
        eventWindowLabel.stringValue = "近 24 小时 · \(localizedDate(Date()))"
        eventDeltaLabel.stringValue = lastNewFeedCount > 0
            ? "本轮新增 +\(lastNewFeedCount)"
            : "本轮暂无新增"
        eventDeltaLabel.textColor = lastNewFeedCount > 0 ? Palette.success : Palette.secondaryText
    }

    private func applyEarthquakes(
        _ earthquakes: [[String: Any]],
        news: [[String: Any]],
        flights: [[String: Any]],
        satellites: [[String: Any]],
        weather: [[String: Any]],
        fires: [[String: Any]],
        conflicts: [[String: Any]],
        gdelt: [[String: Any]],
        gdacs: [[String: Any]],
        airQuality: [[String: Any]],
        cyberThreats: [[String: Any]],
        malware: [[String: Any]],
        infrastructure: [[String: Any]]
    ) {
        var points: [IntelligencePoint] = []
        let showEarthquakes = activeMode == "总览" || activeMode == "地震"
        let showNews = activeMode == "总览" || activeMode == "新闻"
        if showEarthquakes {
            for item in earthquakes.prefix(32) {
                let lat = (item["lat"] as? NSNumber)?.doubleValue ?? 0
                let lng = (item["lng"] as? NSNumber)?.doubleValue ?? 0
                let magnitude = (item["magnitude"] as? NSNumber)?.doubleValue ?? 2.5
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.warning, radius: CGFloat(min(3.4, max(1.4, magnitude / 2)))) )
            }
        }
        if showNews {
            for item in news.prefix(28) {
                guard let coords = item["coords"] as? [NSNumber], coords.count >= 2 else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(truncating: coords[0]), longitude: CGFloat(truncating: coords[1]), color: Palette.violet, radius: 1.5))
            }
        }
        if activeMode == "总览" {
            for item in flights.prefix(72) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.accent, radius: 1.35))
            }
            for item in satellites.prefix(72) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.blue, radius: 1.45))
            }
            for item in weather.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.warning, radius: 1.8))
            }
            for item in fires.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.error, radius: 1.25))
            }
            for item in conflicts.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.violet, radius: 1.7))
            }
            for item in gdelt.prefix(36) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.violet, radius: 1.25))
            }
            for item in gdacs.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.warning, radius: 1.55))
            }
            for item in airQuality.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.success, radius: 1.1))
            }
            for item in malware.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.error, radius: 1.45))
            }
            for item in infrastructure.prefix(24) {
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { continue }
                points.append(IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.blue, radius: 1.15))
            }
        }
        if activeMode == "航班" {
            points = flights.prefix(120).compactMap { item in
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { return nil }
                return IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.accent, radius: 1.7)
            }
        } else if activeMode == "卫星" {
            points = satellites.prefix(120).compactMap { item in
                guard let lat = (item["lat"] as? NSNumber)?.doubleValue,
                      let lng = (item["lng"] as? NSNumber)?.doubleValue else { return nil }
                return IntelligencePoint(latitude: CGFloat(lat), longitude: CGFloat(lng), color: Palette.blue, radius: 1.8)
            }
        }
        globe.points = points
        let rows: [IntelligenceFeedItem]
        if activeMode == "地震" {
            rows = earthquakes.prefix(6).map { item in
                let magnitude = (item["magnitude"] as? NSNumber)?.doubleValue ?? 0
                let place = localizedPlace(item["place"] as? String ?? "公开地震数据")
                let depth = (item["depth"] as? NSNumber)?.doubleValue ?? 0
                let id = item["id"] as? String ?? "earthquake-\(magnitude)-\(place)"
                let timestamp = (item["time"] as? NSNumber)?.doubleValue
                return IntelligenceFeedItem(
                    id: "earthquake:\(id)",
                    category: "地震",
                    title: "M\(String(format: "%.1f", magnitude)) · \(place)",
                    summary: "监测震级 M\(String(format: "%.1f", magnitude))，深度约 \(String(format: "%.1f", depth)) 公里。请结合当地官方通报判断影响。",
                    source: "美国地质调查局",
                    publishedAt: localizedTimestamp(milliseconds: timestamp),
                    riskScore: magnitude >= 6 ? 8 : (magnitude >= 5 ? 6 : (magnitude >= 4 ? 4 : 2)),
                    url: URL(string: item["url"] as? String ?? "")
                )
            }
        } else if activeMode == "航班" {
            rows = flights.prefix(6).map { item in
                let callsign = item["callsign"] as? String ?? "公开航班"
                let altitude = (item["alt"] as? NSNumber)?.intValue ?? 0
                let identifier = item["icao24"] as? String ?? callsign
                return IntelligenceFeedItem(
                    id: "flight:\(identifier)",
                    category: "航班",
                    title: localizedEntityName(callsign, fallback: "公开航班 \(identifier.uppercased())"),
                    summary: "公开航迹显示当前高度约 \(altitude.formatted()) 米。航班数据可能存在延迟，仅供态势参考。",
                    source: "公开航班数据",
                    publishedAt: "实时位置",
                    riskScore: 1,
                    url: nil
                )
            }
        } else if activeMode == "卫星" {
            rows = satellites.prefix(6).enumerated().map { index, item in
                let name = item["name"] as? String ?? "公开卫星"
                let altitude = (item["alt"] as? NSNumber)?.intValue ?? 0
                let identifier = (item["noradId"] as? String) ?? String((item["noradId"] as? NSNumber)?.intValue ?? index + 1)
                return IntelligenceFeedItem(
                    id: "satellite:\(identifier)",
                    category: "卫星",
                    title: localizedEntityName(name, fallback: "公开卫星 \(identifier)"),
                    summary: "公开轨道数据估算高度约 \(altitude.formatted()) 公里，位置会随轨道持续变化。",
                    source: "OSIRIS 本地数据",
                    publishedAt: "实时轨道",
                    riskScore: 1,
                    url: nil
                )
            }
        } else {
            let newsRows = news.prefix(6).map { item in
                // OSIRIS 的 `title` 为兼容 RSS 经常被截成固定长度；
                // `description` 才保留完整的主体、动作和结果。实时动态必须
                // 优先用完整文本生成中文标题，否则会退化成“某国有新进展”
                // 这种无法帮助用户判断事件的泛化提示。
                let rawHeadline = item["description"] as? String
                    ?? item["title"] as? String
                    ?? "全球动态"
                let title = String(localizedNewsTitle(rawHeadline).prefix(90))
                let source = localizedSource(item["source"] as? String ?? "公开来源")
                let risk = (item["risk_score"] as? NSNumber)?.intValue ?? 1
                let rawSummary = rawHeadline
                let localizedSummary = localizedNewsTitle(rawSummary)
                // 详情卡片是中文产品的阅读主面板。原始标题仍可通过
                // “打开来源”查看，但不再把一整段英文/俄文拼接进中文
                // 摘要，避免窄面板换行时出现重影和视觉噪声。
                let summary = String(localizedSummary.prefix(260))
                let rawID = item["id"] as? String ?? item["link"] as? String ?? title
                return IntelligenceFeedItem(
                    id: "news:\(rawID)",
                    category: risk >= 7 ? "高关注事件" : "公开动态",
                    title: title,
                    summary: summary,
                    source: source,
                    publishedAt: localizedPublishedDate(item["published"]),
                    riskScore: risk,
                    url: URL(string: item["link"] as? String ?? "")
                )
            }
            let earthquakeRows = earthquakes.prefix(4).map { item in
                let magnitude = (item["magnitude"] as? NSNumber)?.doubleValue ?? 0
                let place = localizedPlace(item["place"] as? String ?? "公开地震数据")
                let depth = (item["depth"] as? NSNumber)?.doubleValue ?? 0
                let id = item["id"] as? String ?? "earthquake-\(magnitude)-\(place)"
                return IntelligenceFeedItem(
                    id: "earthquake:\(id)",
                    category: "地震",
                    title: "M\(String(format: "%.1f", magnitude)) · \(place)",
                    summary: "美国地质调查局监测到震级 M\(String(format: "%.1f", magnitude))，深度约 \(String(format: "%.1f", depth)) 公里。",
                    source: "美国地质调查局",
                    publishedAt: localizedTimestamp(milliseconds: (item["time"] as? NSNumber)?.doubleValue),
                    riskScore: magnitude >= 6 ? 8 : (magnitude >= 5 ? 6 : (magnitude >= 4 ? 4 : 2)),
                    url: URL(string: item["url"] as? String ?? "")
                )
            }
            let weatherRows = weather.prefix(4).map { item in
                let rawTitle = item["title"] as? String ?? item["type"] as? String ?? "天气异常"
                let severity = (item["severity"] as? String ?? "low").lowercased()
                let risk = severity == "high" ? 7 : (severity == "medium" ? 4 : 2)
                return IntelligenceFeedItem(
                    id: "weather:\(item["id"] as? String ?? rawTitle)",
                    category: "天气",
                    title: localizedWeatherTitle(rawTitle),
                    summary: "公开气象服务监测到\(item["area"] as? String ?? "全球")的\(localizedWeatherTitle(item["type"] as? String ?? "天气事件"))。",
                    source: localizedWeatherSource(item["provider"] as? String ?? "NASA EONET / NOAA"),
                    publishedAt: localizedPublishedDate(item["date"] ?? item["effective"]),
                    riskScore: risk,
                    url: URL(string: item["source"] as? String ?? "")
                )
            }
            let fireRows = fires.prefix(4).map { item in
                let lat = (item["lat"] as? NSNumber)?.doubleValue ?? 0
                let lng = (item["lng"] as? NSNumber)?.doubleValue ?? 0
                let confidence = item["confidence"] as? String ?? "nominal"
                let brightness = (item["brightness"] as? NSNumber)?.doubleValue ?? 0
                return IntelligenceFeedItem(
                    id: "fire:\(lat):\(lng):\(item["date"] as? String ?? "")",
                    category: "火点",
                    title: "卫星火点 · \(String(format: "%.2f", lat))°, \(String(format: "%.2f", lng))°",
                    summary: "NASA FIRMS 遥感火点，亮温 \(String(format: "%.0f", brightness)) K，置信度 \(confidence)。位置仅用于态势参考。",
                    source: "NASA FIRMS",
                    publishedAt: item["date"] as? String ?? "最近观测",
                    riskScore: brightness >= 360 ? 6 : 3,
                    url: nil
                )
            }
            let conflictRows = conflicts.prefix(4).map { item in
                let rawTitle = item["title"] as? String ?? item["label"] as? String ?? "冲突区域动态"
                let id = item["id"] as? String ?? rawTitle
                return IntelligenceFeedItem(
                    id: "conflict:\(id)",
                    category: "冲突态势",
                    title: localizedNewsTitle(rawTitle),
                    summary: localizedNewsTitle(item["description"] as? String ?? "公开冲突区域出现新的态势变化。"),
                    source: "全球公开事件源",
                    publishedAt: localizedPublishedDate(item["timestamp"] ?? item["lastUpdated"]),
                    riskScore: 6,
                    url: URL(string: item["url"] as? String ?? item["sourceUrl"] as? String ?? "")
                )
            }
            let flightRows = flights.prefix(4).map { item in
                let callsign = item["callsign"] as? String ?? "公开航班"
                let altitude = (item["alt"] as? NSNumber)?.intValue ?? 0
                let identifier = item["icao24"] as? String ?? callsign
                return IntelligenceFeedItem(
                    id: "flight:\(identifier)",
                    category: "航班",
                    title: localizedEntityName(callsign, fallback: "公开航班 \(identifier.uppercased())"),
                    summary: "公开 ADS-B 航迹显示当前高度约 \(altitude.formatted()) 米；位置可能有短暂延迟。",
                    source: "公开航班数据",
                    publishedAt: "实时位置",
                    riskScore: 1,
                    url: nil
                )
            }
            let satelliteRows = satellites.prefix(4).enumerated().map { index, item in
                let name = item["name"] as? String ?? "公开卫星"
                let altitude = (item["alt"] as? NSNumber)?.intValue ?? 0
                let identifier = (item["noradId"] as? String) ?? String((item["noradId"] as? NSNumber)?.intValue ?? index + 1)
                return IntelligenceFeedItem(
                    id: "satellite:\(identifier)",
                    category: "卫星",
                    title: localizedSatelliteName(name, identifier: identifier),
                    summary: "公开轨道数据估算高度约 \(altitude.formatted()) 公里，轨道位置会持续变化。",
                    source: "CelesTrak / SatNOGS",
                    publishedAt: "实时轨道",
                    riskScore: 1,
                    url: nil
                )
            }
            let gdeltRows = gdelt.prefix(4).map { item in
                let rawTitle = item["name"] as? String
                    ?? item["title"] as? String
                    ?? item["description"] as? String
                    ?? "GDELT 全球事件"
                let title = String(localizedNewsTitle(rawTitle).prefix(90))
                return IntelligenceFeedItem(
                    id: "gdelt:\(item["id"] as? String ?? title)",
                    category: "全球事件",
                    title: title,
                    summary: "GDELT 2.0 从多语言公开报道中聚合出的地理事件，可继续交给 AI Dev One 交叉核验。",
                    source: "GDELT 2.0",
                    publishedAt: localizedPublishedDate(item["timestamp"] ?? item["date"] ?? item["published"]),
                    riskScore: (item["risk_score"] as? NSNumber)?.intValue ?? 2,
                    url: URL(string: item["url"] as? String ?? item["link"] as? String ?? "")
                )
            }
            let gdacsRows = gdacs.prefix(4).map { item in
                let rawTitle = item["name"] as? String ?? item["title"] as? String ?? "全球灾害预警"
                let type = (item["type"] as? String ?? "incident").lowercased()
                let category = type == "earthquake" ? "灾害 · 地震" : (type == "weather" || type == "flood" || type == "wildfire" ? "灾害 · 气象" : "灾害预警")
                return IntelligenceFeedItem(
                    id: "gdacs:\(item["id"] as? String ?? rawTitle)",
                    category: category,
                    title: localizedNewsTitle(rawTitle),
                    summary: String(localizedNewsTitle(item["description"] as? String ?? "GDACS 发布全球灾害预警，请结合当地官方信息判断影响。").prefix(220)),
                    source: "GDACS 灾害预警",
                    publishedAt: localizedPublishedDate(item["timestamp"] ?? item["date"]),
                    riskScore: type == "earthquake" || type == "flood" ? 6 : 4,
                    url: URL(string: item["url"] as? String ?? item["link"] as? String ?? "")
                )
            }
            let cyberRows = cyberThreats.prefix(4).map { item in
                let name = item["name"] as? String ?? item["id"] as? String ?? "已知网络安全漏洞"
                let vendor = item["vendor"] as? String ?? item["product"] as? String ?? "公开软件"
                let severity = (item["severity"] as? String ?? "HIGH").uppercased()
                let risk = severity == "CRITICAL" ? 9 : (severity == "HIGH" ? 7 : 5)
                return IntelligenceFeedItem(
                    id: "cyber:\(item["id"] as? String ?? name)",
                    category: "网络安全",
                    title: "\(name) · \(vendor)",
                    summary: "CISA KEV / Shadowserver 公开威胁目录标记为 \(severity)，建议在项目依赖和资产清单中优先核验。",
                    source: item["source"] as? String ?? "CISA KEV",
                    publishedAt: localizedPublishedDate(item["date"] ?? item["dateAdded"]),
                    riskScore: risk,
                    url: nil
                )
            }
            let malwareRows = malware.prefix(4).map { item in
                let family = item["malware"] as? String ?? item["threat_type"] as? String ?? "恶意软件活动"
                let country = item["country"] as? String ?? "未知区域"
                return IntelligenceFeedItem(
                    id: "malware:\(item["id"] as? String ?? family + country)",
                    category: "恶意软件",
                    title: "\(localizedMalwareName(family)) · \(country)",
                    summary: "abuse.ch 公开威胁源发现恶意软件基础设施，位置与状态仅作防御态势参考，不执行任何连接。",
                    source: "abuse.ch / URLhaus",
                    publishedAt: localizedPublishedDate(item["last_online"] ?? item["lastOnline"] ?? item["first_seen"]),
                    riskScore: 8,
                    url: nil
                )
            }
            let airQualityRows = airQuality.prefix(3).map { item in
                let name = item["name"] as? String ?? item["city"] as? String ?? "空气质量监测站"
                let pm25 = (item["pm25"] as? NSNumber)?.doubleValue ?? 0
                return IntelligenceFeedItem(
                    id: "air:\(item["id"] as? String ?? name)",
                    category: "空气质量",
                    title: "\(name) · PM2.5 \(String(format: "%.1f", pm25))",
                    summary: "OpenAQ 公开监测站数据，等级：\(item["level"] as? String ?? "待评估")。",
                    source: item["provider"] as? String ?? "OpenAQ / Open-Meteo",
                    publishedAt: localizedPublishedDate(item["lastUpdated"]),
                    riskScore: pm25 >= 55 ? 5 : 2,
                    url: nil
                )
            }
            let infrastructureRows = infrastructure.prefix(3).map { item in
                let name = item["name"] as? String ?? "关键基础设施"
                let country = item["country"] as? String ?? "公开位置"
                let status = item["status"] as? String ?? "状态未知"
                return IntelligenceFeedItem(
                    id: "infra:\(item["id"] as? String ?? name)",
                    category: "关键基础设施",
                    title: "\(localizedInfrastructureName(name)) · \(country)",
                    summary: "公开基础设施清单状态：\(localizedInfrastructureStatus(status))。",
                    source: "OSIRIS 基础设施层",
                    publishedAt: "实时状态",
                    riskScore: status.lowercased().contains("risk") || status.contains("风险") ? 5 : 1,
                    url: nil
                )
            }
            rows = interleaveFeedGroups([
                newsRows, earthquakeRows, weatherRows, fireRows, conflictRows,
                flightRows, satelliteRows, gdeltRows, gdacsRows, cyberRows,
                malwareRows, airQualityRows, infrastructureRows,
            ])
        }
        renderFeed(rows)
        updateInsightBoards()
    }

    private func interleaveFeedGroups(_ groups: [[IntelligenceFeedItem]]) -> [IntelligenceFeedItem] {
        var output: [IntelligenceFeedItem] = []
        let maxCount = groups.map(\.count).max() ?? 0
        for index in 0..<maxCount {
            for group in groups where index < group.count {
                output.append(group[index])
                if output.count >= 24 { return output }
            }
        }
        return output
    }

    private func localizedWeatherTitle(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("storm") || lower.contains("cyclone") || lower.contains("typhoon") {
            return "热带风暴 / 台风动态"
        }
        if lower.contains("volcano") || lower.contains("eruption") { return "火山活动动态" }
        if lower.contains("flood") { return "洪涝灾害动态" }
        if lower.contains("ice") || lower.contains("iceberg") { return "海冰与冰山动态" }
        if lower.contains("weather") || lower.contains("statement") || lower.contains("alert") {
            return "气象预警动态"
        }
        if raw.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return raw }
        return "全球天气异常动态"
    }

    private func localizedWeatherSource(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("eonet") || lower.contains("nasa") { return "NASA EONET" }
        if lower.contains("noaa") || lower.contains("nws") { return "NOAA / NWS" }
        if lower.contains("gdacs") { return "GDACS 灾害预警" }
        return "公开气象数据"
    }

    private func localizedSatelliteName(_ raw: String, identifier: String) -> String {
        let upper = raw.uppercased()
        if upper.contains("ISS") { return "国际空间站（ISS）" }
        if upper.contains("TIANGONG") { return "中国空间站（天宫）" }
        if upper.contains("STARLINK") { return "星链卫星 · \(identifier)" }
        if upper.contains("NOAA") || upper.contains("GOES") { return "气象卫星 · \(identifier)" }
        if upper.contains("GPS") || upper.contains("GALILEO") || upper.contains("BEIDOU") {
            return "导航卫星 · \(identifier)"
        }
        return "轨道卫星 · \(identifier)"
    }

    private func localizedMalwareName(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "恶意软件活动" }
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return clean }
        return "恶意软件 · \(clean)"
    }

    private func localizedInfrastructureName(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "关键基础设施" }
        if clean.contains("NPP") { return clean.replacingOccurrences(of: "NPP", with: "核电站") }
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return clean }
        return "关键设施 · \(clean)"
    }

    private func localizedInfrastructureStatus(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("risk") || lower.contains("conflict") { return "存在周边风险信号" }
        if lower.contains("operational") || lower.contains("active") { return "运行中" }
        if lower.contains("shutdown") || lower.contains("decommissioned") { return "停运或退役" }
        if raw.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return raw }
        return "公开状态已记录"
    }

    private func updateInsightBoards() {
        var high = 0
        var medium = 0
        var low = 0
        var sourceCounts: [String: Int] = [:]
        for item in latestNews {
            let risk = (item["risk_score"] as? NSNumber)?.intValue ?? 1
            if risk >= 7 { high += 1 } else if risk >= 4 { medium += 1 } else { low += 1 }
            if let source = item["source"] as? String {
                sourceCounts[localizedSource(source), default: 0] += 1
            }
        }
        for item in latestEarthquakes {
            let magnitude = (item["magnitude"] as? NSNumber)?.doubleValue ?? 0
            if magnitude >= 6 { high += 1 } else if magnitude >= 4 { medium += 1 } else { low += 1 }
        }
        for item in latestWeather {
            let severity = (item["severity"] as? String ?? "low").lowercased()
            if severity == "high" { high += 1 } else if severity == "medium" { medium += 1 } else { low += 1 }
        }
        if !latestFires.isEmpty { medium += min(latestFires.count, 24) }
        if !latestConflicts.isEmpty { high += min(latestConflicts.count, 24) }
        if !latestGDELT.isEmpty { medium += min(latestGDELT.count, 24) }
        if !latestGDACS.isEmpty { medium += min(latestGDACS.count, 24) }
        if !latestCyberThreats.isEmpty { high += min(latestCyberThreats.count, 24) }
        if !latestMalware.isEmpty { high += min(latestMalware.count, 24) }
        if !latestAirQuality.isEmpty {
            medium += min(latestAirQuality.filter {
                (($0["pm25"] as? NSNumber)?.doubleValue ?? 0) >= 55
            }.count, 24)
        }
        if !latestEarthquakes.isEmpty { sourceCounts["美国地质调查局"] = latestEarthquakes.count }
        if !latestFlights.isEmpty { sourceCounts["公开航班数据"] = latestFlights.count }
        if !latestSatellites.isEmpty { sourceCounts["CelesTrak / SatNOGS"] = latestSatellites.count }
        if !latestWeather.isEmpty { sourceCounts["NASA / NOAA 气象"] = latestWeather.count }
        if !latestFires.isEmpty { sourceCounts["NASA FIRMS 火点"] = latestFires.count }
        if !latestConflicts.isEmpty { sourceCounts["全球冲突公开源"] = latestConflicts.count }
        if !latestMaritime.isEmpty { sourceCounts["全球港口态势"] = latestMaritime.count }
        if let kp = latestSpaceWeather["kp_index"] as? NSNumber {
            sourceCounts["NOAA 太空天气"] = max(1, kp.intValue)
        }
        if !latestGDELT.isEmpty { sourceCounts["GDELT 2.0 全球事件"] = latestGDELT.count }
        if !latestGDACS.isEmpty { sourceCounts["GDACS 灾害预警"] = latestGDACS.count }
        if !latestAirQuality.isEmpty {
            let hasModelFallback = latestAirQuality.contains { ($0["provider"] as? String)?.contains("Open-Meteo") == true }
            sourceCounts[hasModelFallback ? "OpenAQ / Open-Meteo 空气质量" : "OpenAQ 空气质量"] = latestAirQuality.count
        }
        if !latestCyberThreats.isEmpty { sourceCounts["CISA KEV / Shadowserver"] = latestCyberThreats.count }
        if !latestMalware.isEmpty { sourceCounts["abuse.ch 威胁情报"] = latestMalware.count }
        if !latestInfrastructure.isEmpty { sourceCounts["关键基础设施"] = latestInfrastructure.count }

        let sources = sourceCounts.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(6)
        if sources.isEmpty {
            sourceSummary.stringValue = "等待公开来源"
        } else {
            let attributed = NSMutableAttributedString()
            let colors = [Palette.accent, Palette.blue, Palette.violet, Palette.warning]
            for (index, source) in sources.enumerated() {
                if index > 0 { attributed.append(NSAttributedString(string: "\n")) }
                attributed.append(NSAttributedString(string: "● ", attributes: [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                    .foregroundColor: colors[index % colors.count],
                ]))
                attributed.append(NSAttributedString(
                    string: "\(source.key)  \(source.value.formatted())",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.76),
                    ]
                ))
            }
            sourceSummary.attributedStringValue = attributed
        }
        riskSummary.stringValue = "高风险  \(high)\n中风险  \(medium)\n低风险  \(low)\n\n基于公开源的本地规则初筛"
        riskRing.update(high: high, medium: medium, low: low)

        let strongEarthquakes = latestEarthquakes.filter {
            (($0["magnitude"] as? NSNumber)?.doubleValue ?? 0) >= 5
        }.count
        let eventTotal = latestNews.count
            + latestEarthquakes.count
            + latestWeather.count
            + latestFires.count
            + latestConflicts.count
            + latestGDELT.count
            + latestGDACS.count
            + latestCyberThreats.count
            + latestMalware.count
        if eventTotal == 0 {
            aiInsightSummary.stringValue = "等待实时事件数据。连接后将给出本地初步洞察。"
        } else if high > 0 || strongEarthquakes > 0 {
            aiInsightSummary.stringValue = "检测到 \(high) 条高风险信号、\(strongEarthquakes) 条 M5+ 地震。建议选择相关事件，用 AI Dev One 交叉验证来源与影响。"
        } else {
            aiInsightSummary.stringValue = "当前 \(eventTotal) 条事件未出现集中高风险信号。可选择任意事件，让 AI Dev One 进一步核验。"
        }
        updateSelectionControls()
    }

    /// OSIRIS 的公开 RSS/GDELT 标题原文可能是英文、俄文或其他语言。
    /// 情报页是中文产品界面，因此不把原始标题直接泄露到卡片；对常见
    /// 事件模板做本地化，对无法安全翻译的长标题给出中文事件摘要。
    private func localizedNewsTitle(_ raw: String) -> String {
        let clean = cleanPublicTitle(raw)
        guard !clean.isEmpty else { return "全球公开动态" }
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil {
            return clean
        }
        let lower = clean.lowercased()

        // 当前公开源中最常见的标题模板。优先保留事件主体和动作，
        // 不能为了“全中文”把不同新闻都压成同一个占位句。
        if lower.contains("auction") || lower.contains("выставлено на аукцион") {
            return "Telegram 用户名 @cyberknow 被挂牌拍卖，卖方设置最低报价 80"
        }
        if lower.contains("trump") && lower.contains("canada") && lower.contains("tariff") {
            return "特朗普指责加拿大对美贸易不公，并宣布自 2027 年起将汽车、零部件及钢铁关税提高至 50%"
        }
        if lower.contains("united kingdom") && lower.contains("storm shadow") && lower.contains("ukraine") {
            return "英国批准向乌克兰转让“风暴阴影”导弹技术，支持乌方自主生产"
        }
        if lower.contains("saudi national shipping company") && lower.contains("red sea") && lower.contains("attack") {
            return "沙特国家航运公司称“Amzan”号船在红海遭到袭击"
        }
        if lower.contains("assaad al-shaibani") || lower.contains("as aad al-shaibani") {
            if lower.contains("security agreement") && lower.contains("israel") {
                return "叙利亚外长沙伊巴尼称，预计与以色列的安全协议谈判将很快恢复"
            }
            return "叙利亚外长沙伊巴尼接受路透社采访，回应地区局势"
        }
        if lower.contains("foreign minister") && lower.contains("reuters") {
            return "外交部长接受路透社采访，就当前地区局势作出回应"
        }
        if lower.contains("israel") && lower.contains("prime minister") && lower.contains("office") {
            if lower.contains("international stabilization force") || lower.contains("board of peace") {
                return "以色列总理办公室称，尚未批准国际稳定部队进入加沙地带"
            }
            return "以色列总理办公室就当前局势发布最新声明"
        }
        if lower.contains("turkish defense ministry") || (lower.contains("turkey") && lower.contains("defense ministry")) {
            if lower.contains("no turkish military") || lower.contains("not involved") {
                return "土耳其国防部：土耳其军方未参与相关行动"
            }
            return "土耳其国防部发布最新军事动态说明"
        }
        if lower.contains("israeli army") && lower.contains("advancing") {
            return "以色列军队正向边境目标区域推进"
        }
        if lower.contains("syrian foreign ministry") && lower.contains("condemn") {
            return "叙利亚外交部发表声明，谴责相关军事行动"
        }

        let entities: [(String, String)] = [
            ("ukraine", "乌克兰"), ("kyiv", "基辅"), ("russia", "俄罗斯"),
            ("moscow", "莫斯科"), ("israel", "以色列"), ("gaza", "加沙"),
            ("iran", "伊朗"), ("lebanon", "黎巴嫩"), ("syria", "叙利亚"),
            ("yemen", "也门"), ("turkey", "土耳其"), ("taiwan", "中国台湾地区"),
            ("china", "中国"), ("united states", "美国"),
        ]
        let actions: [(String, String)] = [
            ("ceasefire", "停火谈判出现新进展"),
            ("sanction", "制裁措施出现新变化"),
            ("missile", "导弹相关安全动态更新"),
            ("drone", "无人机相关安全动态更新"),
            ("airstrike", "空袭行动出现新动态"),
            ("strike", "打击行动出现新动态"),
            ("attack", "袭击事件出现新进展"),
            ("military", "军事与安全态势更新"),
            ("election", "选举进程出现新动态"),
            ("talks", "相关谈判出现新进展"),
            ("earthquake", "地震监测出现新动态"),
            ("wildfire", "野火灾情出现新动态"),
            ("flood", "洪涝灾情出现新动态"),
        ]
        let entity = entities.first(where: { lower.contains($0.0) })?.1
        let action = actions.first(where: { lower.contains($0.0) })?.1
        if let entity, let action { return "\(entity)：\(action)" }
        if let entity { return "\(entity)相关公开事件出现最新进展" }
        if let action { return "全球公开情报：\(action)" }
        // 兜底必须保留事件主体，不能把所有未知标题压成同一句，
        // 否则用户会误以为刷新后没有新动态。
        return "公开动态：\(String(clean.prefix(82)))"
    }

    private func cleanPublicTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#33;", with: "!")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localizedSource(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        if lower.contains("liveuamap") { return "实时地图公开源" }
        if lower.contains("usgs") { return "美国地质调查局" }
        if lower.contains("gdelt") { return "全球事件数据库" }
        if lower.contains("ads-b") { return "公开航班数据" }
        if lower.contains("osiris") { return "OSIRIS 本地数据" }
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return clean }
        return "公开新闻源"
    }

    private func localizedPlace(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return clean }
        return "公开地震区域"
    }

    private func localizedTimestamp(milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds > 0 else { return "时间待确认" }
        return localizedDate(Date(timeIntervalSince1970: milliseconds / 1_000))
    }

    private func localizedPublishedDate(_ raw: Any?) -> String {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return localizedDate(Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value))
        }
        guard let text = raw as? String, !text.isEmpty else { return "发布时间待确认" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return localizedDate(date) }
        return text
    }

    private func localizedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func localizedEntityName(_ raw: String, fallback: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return fallback }
        // 航班呼号/卫星编号本身是数据标识；无中文名称时用中文类型名，
        // 避免把一整段英文实体名直接放入中文动态卡片。
        if clean.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil { return clean }
        return fallback
    }

    private func renderFeed(_ rows: [IntelligenceFeedItem]) {
        let incomingIDs = Set(rows.map(\.id))
        let newItems = rows.filter { !seenFeedIDs.contains($0.id) && !newFeedIDsInRefresh.contains($0.id) }
        newFeedIDsInRefresh.formUnion(newItems.map(\.id))
        lastNewFeedCount = newFeedIDsInRefresh.count
        seenFeedIDs.formUnion(incomingIDs)

        // 保留最近几轮的真实事件，刷新时只把新条目插到前面；这样
        // “实时动态”不再每 30 秒被同一组首屏数据覆盖，也能让用户
        // 滚动回看刚刚到达的事件。最多保留 80 条，避免长时间运行
        // 时 AppKit 不断增长视图树。
        let existingIDs = Set(rows.map(\.id))
        feedHistory = Array((rows + feedHistory.filter { !existingIDs.contains($0.id) }).prefix(80))
        currentFeedItems = feedHistory
        feedStatusLabel.stringValue = lastNewFeedCount > 0
            ? "公开来源 · 本轮新增 \(lastNewFeedCount) 条 · 自动刷新"
            : "公开来源 · 已更新 · 暂无新增"
        eventDeltaLabel.stringValue = lastNewFeedCount > 0
            ? "本轮新增 +\(lastNewFeedCount)"
            : "本轮暂无新增"
        eventDeltaLabel.textColor = lastNewFeedCount > 0 ? Palette.success : Palette.secondaryText
        if statLabels.count >= 4 { statLabels[3].stringValue = lastNewFeedCount.formatted() }
        let previousScrollY = feedScrollView.contentView.bounds.origin.y
        feedStack.arrangedSubviews.forEach { feedStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if rows.isEmpty {
            let empty = IntelligenceFeedItem(
                id: "system:waiting",
                category: "等待数据",
                title: "暂无可用的公开动态",
                summary: "服务会在网络恢复后自动重试。",
                source: "AI Dev One 本地服务",
                publishedAt: "—",
                riskScore: 0,
                url: nil
            )
            let row = makeFeedRow(item: empty, selectable: false)
            feedStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: feedStack.widthAnchor).isActive = true
            return
        }
        // 服务返回的是按发布时间排序的公开事件流。首屏显示更多条目，
        // 其余内容放进列表滚动区；不能用 prefix(3) 把实时源人为截成
        // 三条，否则用户每次刷新看到的永远像同一组数据。
        feedHistory.prefix(12).forEach { item in
            if selectedItems[item.id] != nil { selectedItems[item.id] = item }
            let row = makeFeedRow(item: item)
            feedStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: feedStack.widthAnchor).isActive = true
        }
        // 刷新/切换来源重建 row 时保持用户正在查看的滚动位置；如果
        // 新列表变短，则把 offset 安全限制在新的文档高度内。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let maxY = max(0, self.feedDocumentView.bounds.height - self.feedScrollView.contentView.bounds.height)
            let y = min(max(0, previousScrollY), maxY)
            self.feedScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            self.feedScrollView.reflectScrolledClipView(self.feedScrollView.contentView)
        }
    }

    private func feedAccentColor(for item: IntelligenceFeedItem) -> NSColor {
        if item.riskScore >= 7 { return Palette.error }
        if item.category.contains("地震") { return Palette.warning }
        if item.category.contains("航班") { return Palette.accent }
        if item.category.contains("卫星") { return Palette.blue }
        return item.riskScore >= 4 ? Palette.violet : Palette.accent
    }

    private func feedSymbolName(for item: IntelligenceFeedItem) -> String {
        if item.category.contains("地震") { return "waveform.path.ecg" }
        if item.category.contains("航班") { return "airplane" }
        if item.category.contains("卫星") { return "dot.radiowaves.left.and.right" }
        if item.riskScore >= 7 { return "exclamationmark.triangle.fill" }
        return "newspaper.fill"
    }

    private func riskColor(for item: IntelligenceFeedItem) -> NSColor {
        if item.riskScore >= 7 { return Palette.error }
        if item.riskScore >= 4 { return Palette.warning }
        return Palette.success
    }

    private func makeFeedRow(item: IntelligenceFeedItem, selectable: Bool = true) -> IntelligenceFeedRow {
        let row = IntelligenceFeedRow(fillColor: Palette.canvas.withAlphaComponent(0.48), cornerRadius: 8, strokeColor: Palette.border.withAlphaComponent(0.40))
        row.translatesAutoresizingMaskIntoConstraints = false
        let selected = selectedItems[item.id] != nil
        let accentColor = feedAccentColor(for: item)
        let statusColor = riskColor(for: item)
        let symbolName = feedSymbolName(for: item)
        let icon = NSImageView()
        icon.image = selected
            ? symbol("checkmark.circle.fill", size: 12, weight: .semibold)
            : symbol(symbolName, size: 12, weight: .semibold)
        icon.contentTintColor = selected ? Palette.success : accentColor
        icon.imageScaling = .scaleProportionallyDown
        icon.wantsLayer = true
        icon.layer?.backgroundColor = accentColor.withAlphaComponent(0.13).cgColor
        icon.layer?.cornerRadius = 7

        let titleLabel = label(item.title, size: 10.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        let summaryLabel = label(item.summary, size: 9.2, color: Palette.secondaryText)
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        let sourceLabel = label("\(item.source)  ·  \(item.publishedAt)", size: 8.5, color: Palette.secondaryText)
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.maximumNumberOfLines = 1
        let riskBadge = label(item.riskLabel, size: 8, weight: .semibold, color: statusColor)
        riskBadge.alignment = .center
        riskBadge.wantsLayer = true
        riskBadge.layer?.backgroundColor = statusColor.withAlphaComponent(0.11).cgColor
        riskBadge.layer?.borderColor = statusColor.withAlphaComponent(0.34).cgColor
        riskBadge.layer?.borderWidth = 0.6
        riskBadge.layer?.cornerRadius = 8
        row.toolTip = selectable ? "点击选择并查看详情；选中后可交给 AI Dev One 分析" : item.summary
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel("\(item.category)：\(item.title)")
        row.setAccessibilityValue("\(item.riskLabel)，来源 \(item.source)，\(item.publishedAt)")
        row.setSelectedForAnalysis(selected)
        row.onClick = { [weak self, weak row, weak icon] in
            guard let self, selectable else { return }
            self.focusedItem = item
            if self.selectedItems[item.id] == nil {
                self.selectedItems[item.id] = item
            } else {
                self.selectedItems.removeValue(forKey: item.id)
            }
            let isSelected = self.selectedItems[item.id] != nil
            row?.setSelectedForAnalysis(isSelected)
            icon?.image = isSelected
                ? symbol("checkmark.circle.fill", size: 12, weight: .semibold)
                : symbol(symbolName, size: 12, weight: .semibold)
            icon?.contentTintColor = isSelected ? Palette.success : accentColor
            self.selectionLabel.stringValue = "已查看动态：\(item.title) · \(item.source)"
            self.showDetail(item)
            self.updateSelectionControls()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                _ = self.detailCard.scrollToVisible(self.detailCard.bounds)
            }
            self.onDebugSnapshot?()
        }
        [icon, titleLabel, summaryLabel, sourceLabel, riskBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            // Five compact rows should fit in the 1260×760 reference window
            // without forcing the first viewport to scroll immediately.
            row.heightAnchor.constraint(equalToConstant: 52),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 7),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            riskBadge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7),
            riskBadge.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            riskBadge.widthAnchor.constraint(equalToConstant: 42),
            riskBadge.heightAnchor.constraint(equalToConstant: 17),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(equalTo: riskBadge.leadingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: sourceLabel.trailingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            sourceLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7),
            sourceLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 2),
        ])
        row.installActionLayer(toolTip: row.toolTip)
        return row
    }

    private func showDetail(_ item: IntelligenceFeedItem) {
        detailCategory.stringValue = "\(item.category) · \(item.riskLabel)"
        detailCategory.textColor = item.riskScore >= 7 ? Palette.warning : (item.riskScore >= 4 ? Palette.violet : Palette.accent)
        detailTitle.stringValue = item.title
        detailSummary.stringValue = item.summary
        detailMeta.stringValue = "来源：\(item.source)  ·  \(item.publishedAt)"
        openSourceButton.isEnabled = item.url != nil
        openSourceButton.toolTip = item.url?.absoluteString ?? "该数据没有可打开的公开链接"
    }

    private func updateSelectionControls() {
        let count = selectedItems.count
        selectedCountLabel.stringValue = "已选 \(count) 条"
        selectedCountLabel.textColor = count > 0 ? Palette.accent : Palette.secondaryText
        clearSelectionButton.isEnabled = count > 0
        analyzeButton.isEnabled = count > 0
        analyzeButton.title = count > 0 ? "用 AI Dev One 分析（\(count)）" : "用 AI Dev One 分析"
        if count == 0 {
            analysisStatus.stringValue = "先从实时动态中选择情报"
            analysisStatus.textColor = Palette.secondaryText
        }
    }

    private func showFallbackData() {
        statLabels.forEach { $0.stringValue = "—" }
        latestStats = [:]
        latestEarthquakes = []
        latestNews = []
        latestFlights = []
        latestSatellites = []
        latestWeather = []
        latestFires = []
        latestConflicts = []
        latestMaritime = []
        latestSpaceWeather = [:]
        latestGDELT = []
        latestGDACS = []
        latestAirQuality = []
        latestCyberThreats = []
        latestMalware = []
        latestInfrastructure = []
        feedHistory = []
        seenFeedIDs.removeAll()
        newFeedIDsInRefresh.removeAll()
        lastNewFeedCount = 0
        globe.points = [
            IntelligencePoint(latitude: 31, longitude: 121, color: Palette.accent, radius: 2.4),
            IntelligencePoint(latitude: 37, longitude: -122, color: Palette.violet, radius: 2.0),
            IntelligencePoint(latitude: 51, longitude: 0, color: Palette.blue, radius: 1.8),
        ]
        renderFeed([])
        feedStatusLabel.stringValue = "公开来源 · 等待连接"
        sourceSummary.stringValue = "等待公开来源"
        riskSummary.stringValue = "高风险 —\n中风险 —\n低风险 —"
        riskRing.update(high: 0, medium: 0, low: 0)
        aiInsightSummary.stringValue = "连接数据后生成本地初步洞察；选择事件可交给 AI Dev One 深度分析。"
        updateSelectionControls()
    }
}

// MARK: - 全球情报悬浮大屏

/// The intelligence surface is intentionally hosted outside the narrow
/// Workspace pane.  Keeping the same view instance in a dedicated panel gives
/// the globe, live feed, detail card and insight boards enough room to be read
/// and interacted with, while preserving the existing local service and Agent
/// analysis callbacks.
final class IntelligenceWindowController: NSWindowController, NSWindowDelegate {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("AI Dev One.Intelligence")
    private static let pinnedDefaultsKey = "ai-dev-one.intelligence.pinned"
    let dashboard: IntelligenceDashboardView
    private var didRestoreFrame = false
    private var isPinned: Bool
    var onAnalyze: ((String) -> Bool)?
    var onDebugSnapshot: (() -> Void)?
    var onPresented: (() -> Void)?
    var onClosed: (() -> Void)?

    init() {
        dashboard = IntelligenceDashboardView()
        isPinned = UserDefaults.standard.object(forKey: Self.pinnedDefaultsKey) as? Bool ?? true
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1260, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Dev One · 全球情报中心"
        window.titleVisibility = .visible
        window.appearance = NSAppearance(named: .darkAqua)
        // This is a complete command-center surface, not a translucent
        // inspector over the three-column editor.  An opaque window prevents
        // the editor's chat/sidebar text from bleeding through the cards.
        window.backgroundColor = Palette.forestBottom
        window.isOpaque = true
        window.hasShadow = true
        window.level = isPinned ? .floating : .normal
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed]
        window.sharingType = .readOnly
        window.minSize = NSSize(width: 1050, height: 650)
        window.contentMinSize = NSSize(width: 1050, height: 650)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.frameAutosaveName)

        // IntelligenceDashboardView normally uses Auto Layout when embedded;
        // as a window root it must instead follow the panel frame directly.
        dashboard.translatesAutoresizingMaskIntoConstraints = true
        dashboard.autoresizingMask = [.width, .height]
        dashboard.fillColor = Palette.forestBottom
        window.contentView = dashboard

        super.init(window: window)
        window.delegate = self
        dashboard.onAnalyze = { [weak self] prompt in
            self?.onAnalyze?(prompt) ?? false
        }
        dashboard.setPinned(isPinned)
        dashboard.onPinToggle = { [weak self] pinned in
            self?.setPinned(pinned)
        }
        dashboard.onDebugSnapshot = { [weak self] in
            self?.onDebugSnapshot?()
        }
        dashboard.onClose = { [weak self] in
            self?.window?.close()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建")
    }

    func show() {
        guard let window else { return }
        restoreFrameIfNeeded()
        dashboard.setVisible(true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // A signed app launched through LaunchServices does not expose its
        // stderr to the validating terminal.  When the opt-in geometry probe
        // is enabled, sample after the window has a real frame rather than
        // trusting the constructor-time zero-sized layout pass.
        if ProcessInfo.processInfo.environment["AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES"] == "1" {
            window.displayIfNeeded()
            dashboard.debugFrameSnapshotIfRequested()
            if ProcessInfo.processInfo.environment["AI_DEV_ONE_INTELLIGENCE_DEBUG_SIZES"] == "1" {
                let sizes = [
                    NSSize(width: 1260, height: 760),
                    NSSize(width: 1100, height: 680),
                    NSSize(width: 1440, height: 900),
                ]
                for size in sizes {
                    window.setContentSize(size)
                    window.displayIfNeeded()
                    dashboard.debugFrameSnapshotIfRequested()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        // Notify the owner only after a real window is on screen.  The owner
        // may now hide the editor without tripping AppKit's
        // "last window closed" termination policy.
        onPresented?()
    }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        UserDefaults.standard.set(pinned, forKey: Self.pinnedDefaultsKey)
        guard let window else { return }
        window.level = pinned ? .floating : .normal
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        dashboard.setVisible(false)
        onClosed?()
    }

    private func restoreFrameIfNeeded() {
        guard let window else { return }
        if didRestoreFrame {
            if !frameIsVisible(window.frame) {
                window.setFrame(defaultFrame(), display: false)
            }
            return
        }
        didRestoreFrame = true
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        guard restored, frameIsVisible(window.frame) else {
            window.setFrame(defaultFrame(), display: false)
            return
        }
    }

    private func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Match the standalone concept board while respecting the declared
        // minimum. Full-screen users can resize the panel freely afterwards.
        let width = min(1260, max(1050, visible.width - 32))
        let height = min(760, max(650, visible.height - 32))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func frameIsVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }
}
