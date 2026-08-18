import AppKit
import Foundation
import WebKit
import Darwin

#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Browser Visual Verification 数据模型

enum BrowserVerificationStatus: String, Codable {
    case created
    case startingServer = "starting_server"
    case waitingServer = "waiting_server"
    case launchingBrowser = "launching_browser"
    case loadingPage = "loading_page"
    case capturing
    case analyzing
    case passed
    case failed
    case cancelled
    case error
    case skipped
}

enum BrowserFindingSeverity: String, Codable {
    case info
    case warning
    case error
    case critical
}

struct BrowserViewport: Codable, Equatable {
    let width: Int
    let height: Int

    static let desktop = BrowserViewport(width: 1440, height: 900)
    static let laptop = BrowserViewport(width: 1280, height: 800)
    static let mobile = BrowserViewport(width: 390, height: 844)
}

struct BrowserFinding: Codable, Equatable {
    let code: String
    let severity: BrowserFindingSeverity
    let message: String
    let detail: String?
}

struct BrowserScreenshotArtifact: Codable, Equatable {
    let kind: String
    let path: String
    let sha256: String
    let width: Int
    let height: Int
}

struct BrowserVerificationResult: Codable, Equatable {
    let verificationID: String
    let taskID: String?
    let projectID: String?
    let projectPath: String
    let devServerCommand: String?
    let devServerPID: Int32?
    let devServerURL: String?
    let browserRuntime: String
    let browserPID: Int32?
    let startedAt: Date
    let endedAt: Date
    let viewport: BrowserViewport
    let status: BrowserVerificationStatus
    let screenshots: [BrowserScreenshotArtifact]
    let consoleMessages: [String]
    let consoleWarnings: [String]
    let pageErrors: [String]
    let failedRequests: [String]
    let layoutFindings: [BrowserFinding]
    let findings: [BrowserFinding]
    let instrumentationInstalled: Bool
    let timingsMS: [String: Double]
    let summary: String

    var hasBlockingFinding: Bool {
        status == .failed || status == .error
            || findings.contains { $0.severity == .error || $0.severity == .critical }
    }
}

struct BrowserVerificationSession: Codable, Equatable {
    let verificationID: String
    let taskID: String?
    let projectID: String?
    let projectPath: String
    let devServerCommand: String?
    var devServerPID: Int32?
    var devServerURL: String?
    let browserRuntime: String
    var browserPID: Int32?
    let startedAt: Date
    var endedAt: Date?
    var viewport: BrowserViewport
    var status: BrowserVerificationStatus
}

// MARK: - 本地 URL / 凭据边界

enum BrowserURLPolicy {
    static func validate(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func sanitizedString(_ raw: String) -> String {
        guard let url = validate(raw), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<blocked-url>"
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? "<blocked-url>"
    }

    static func isAllowed(_ raw: String) -> Bool { validate(raw) != nil }
}

struct BrowserVerificationConfiguration {
    static let serverStartupTimeout: TimeInterval = 20
    static let pageLoadTimeout: TimeInterval = 20
    static let browserLaunchTimeout: TimeInterval = 8
    static let verificationTimeout: TimeInterval = 45
    static let artifactRetention: TimeInterval = 14 * 24 * 60 * 60
}

// MARK: - Runtime / Dev Server Detection

struct BrowserRuntimeInfo: Codable, Equatable {
    let name: String
    let kind: String
    let executablePath: String?

    static func detect() -> BrowserRuntimeInfo? {
        // WKWebView is part of macOS and does not download a browser binary.
        // A future Playwright/Chromium implementation can replace this driver
        // without changing the verification session contract.
        BrowserRuntimeInfo(name: "macOS WebKit", kind: "wkwebview", executablePath: nil)
    }
}

struct DevServerPlan: Codable, Equatable {
    let command: [String]
    let displayCommand: String
    let configuredURL: String?
    let framework: String?

    static func detect(projectPath: String) -> DevServerPlan? {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let packageURL = root.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any] else { return nil }
        let scriptName = ["dev", "start", "serve", "preview"].first { scripts[$0] != nil }
        guard let scriptName else { return nil }

        let manager: String
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { manager = "pnpm" }
        else if FileManager.default.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { manager = "yarn" }
        else if FileManager.default.fileExists(atPath: root.appendingPathComponent("bun.lockb").path)
                    || FileManager.default.fileExists(atPath: root.appendingPathComponent("bun.lock").path) { manager = "bun" }
        else { manager = "npm" }

        let packageManagerCommand: [String]
        switch manager {
        case "pnpm": packageManagerCommand = ["pnpm", scriptName]
        case "yarn": packageManagerCommand = ["yarn", scriptName]
        case "bun": packageManagerCommand = ["bun", "run", scriptName]
        default: packageManagerCommand = ["npm", "run", scriptName]
        }
        let scriptValue = scripts[scriptName] as? String
        let command: [String]
        if let scriptValue, scriptValue.hasPrefix("node ") {
            command = scriptValue.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        } else {
            command = packageManagerCommand
        }
        let config = json["aiDevOne"] as? [String: Any]
        let browserConfig = config?["browserVerification"] as? [String: Any]
        let configuredURL = browserConfig?["url"] as? String
        let framework = detectFramework(json: json, root: root)
        return DevServerPlan(command: command, displayCommand: packageManagerCommand.joined(separator: " "), configuredURL: configuredURL, framework: framework)
    }

    private static func detectFramework(json: [String: Any], root: URL) -> String? {
        let deps = Set(
            Array((json["dependencies"] as? [String: Any] ?? [:]).keys)
                + Array((json["devDependencies"] as? [String: Any] ?? [:]).keys)
        )
        if deps.contains("next") { return "Next.js" }
        if deps.contains("vite") { return "Vite" }
        if deps.contains("astro") { return "Astro" }
        if deps.contains("svelte") || deps.contains("@sveltejs/kit") { return "Svelte" }
        if deps.contains("nuxt") { return "Nuxt" }
        if deps.contains("react") { return "React" }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("vite.config.ts").path)
            || FileManager.default.fileExists(atPath: root.appendingPathComponent("vite.config.js").path) { return "Vite" }
        return nil
    }
}

enum BrowserVerificationPlanner {
    static func shouldRun(projectPath: String, prompt: String, transaction: TaskTransaction? = nil) -> Bool {
        let lowerPrompt = prompt.lowercased()
        let explicit = ["ui", "frontend", "web", "页面", "界面", "视觉", "浏览器", "响应式", "css", "tsx", "jsx", "vue", "svelte", "html"]
            .contains { lowerPrompt.contains($0) }
        let overview = ProjectIntelligenceService.shared.overview(projectPath: projectPath)
        let frameworks = overview.index?.project.frameworks ?? []
        let frontend = frameworks.contains { ["React", "Vite", "Next.js", "Astro", "Svelte", "Nuxt", "Electron"].contains($0) }
            || DevServerPlan.detect(projectPath: projectPath) != nil
        let changedFrontend = transaction?.fileChanges.contains { path in
            ["ts", "tsx", "js", "jsx", "vue", "svelte", "html", "css", "scss"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        } ?? false
        return frontend && (explicit || changedFrontend)
    }
}

private enum BrowserProcessEnvironment {
    static func merged() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let toolchain = home.appendingPathComponent("Library/Application Support/AI Dev One Installer/toolchains/node/bin")
        let existing = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if FileManager.default.fileExists(atPath: toolchain.path) {
            environment["PATH"] = toolchain.path + ":" + existing
        }
        environment["GROK_TELEMETRY_ENABLED"] = "0"
        environment["DISABLE_TELEMETRY"] = "1"
        // Keep the explicit removals as a readable contract for the two
        // providers currently configured by AI Dev One; the loop below also
        // covers custom routers and future providers.
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "XAI_API_KEY")
        // A local fixture must never inherit model credentials or bearer
        // tokens from the desktop process.  This is intentionally broader
        // than the two providers used by the app so custom routers are also
        // isolated from the visual-verification process.
        for key in Array(environment.keys) {
            let uppercased = key.uppercased()
            if uppercased == "API_KEY"
                || uppercased.hasSuffix("_API_KEY")
                || uppercased == "AUTHORIZATION"
                || uppercased.hasSuffix("_AUTH_TOKEN") {
                environment.removeValue(forKey: key)
            }
        }
        return environment
    }
}

enum BrowserVerificationRedaction {
    private static let patterns = [
        #"(?i)\bsk-[A-Za-z0-9_-]{8,}\b"#,
        #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#,
        #"(?i)\b(?:[A-Z][A-Z0-9_-]*_)?API[_ -]?KEY\s*[:=]\s*[^\s,;]+"#,
        #"(?i)\b(?:authorization|password|secret|token)\s*[:=]\s*[^\s,;]+"#
    ]

    static func text(_ value: String) -> String {
        patterns.reduce(value) { partial, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return partial }
            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return expression.stringByReplacingMatches(in: partial, options: [], range: range, withTemplate: "<redacted>")
        }
    }
}

final class DevServerSupervisor {
    private(set) var process: Process?
    private(set) var ownedProcess = false
    private(set) var lastOutput = ""
    private(set) var lastError: String?

    var isRunning: Bool { process?.isRunning == true }
    var pid: Int32? { process?.processIdentifier }

    func start(
        projectPath: String,
        requestedURL: String?,
        completion: @escaping (Result<(url: String, owned: Bool, pid: Int32?, startupMS: Double), Error>) -> Void
    ) {
        guard process == nil else {
            completion(.failure(Self.error("已有受管开发服务器正在运行")))
            return
        }
        let started = Date()
        let plan = DevServerPlan.detect(projectPath: projectPath)
        let configured = plan?.configuredURL
        let canAttach = requestedURL.flatMap { value in
            guard let configured else { return false }
            return BrowserURLPolicy.sanitizedString(value) == BrowserURLPolicy.sanitizedString(configured)
        } ?? false
        if canAttach, let requestedURL, let url = BrowserURLPolicy.validate(requestedURL) {
            probe(url: url) { [weak self] available in
                guard let self else { return }
                if available {
                    self.ownedProcess = false
                    completion(.success((BrowserURLPolicy.sanitizedString(requestedURL), false, nil, Date().timeIntervalSince(started) * 1000)))
                } else {
                    self.launch(projectPath: projectPath, requestedURL: requestedURL, started: started, completion: completion)
                }
            }
            return
        }
        launch(projectPath: projectPath, requestedURL: requestedURL, started: started, completion: completion)
    }

    func stop(completion: @escaping () -> Void = {}) {
        guard ownedProcess, let task = process else {
            completion()
            return
        }
        let rootPID = task.processIdentifier
        let descendants = Self.descendantPIDs(of: rootPID)
        let startTokens = Dictionary(uniqueKeysWithValues: descendants.map { ($0, Self.processStartToken($0)) })
        for child in descendants.reversed()
            where startTokens[child]?.isEmpty == false && startTokens[child] == Self.processStartToken(child) {
            kill(child, SIGTERM)
        }
        if task.isRunning {
            task.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                for child in descendants where kill(child, 0) == 0
                    && startTokens[child] == Self.processStartToken(child) {
                    kill(child, SIGKILL)
                }
            }
        }
        process = nil
        ownedProcess = false
        let deadline = Date().addingTimeInterval(2)
        func waitForTree() {
            let childAlive = descendants.contains { kill($0, 0) == 0 }
            if task.isRunning || childAlive, Date() < deadline {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.08, execute: waitForTree)
            } else {
                DispatchQueue.main.async(execute: completion)
            }
        }
        waitForTree()
    }

    private static func descendantPIDs(of root: Int32) -> [Int32] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid="]
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        var children: [Int32: [Int32]] = [:]
        for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let pid = Int32(parts[0]), let parent = Int32(parts[1]) else { continue }
            children[parent, default: []].append(pid)
        }
        var result: [Int32] = []
        var queue = children[root] ?? []
        while let next = queue.popLast() {
            result.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    private static func processStartToken(_ pid: Int32) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "lstart="]
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func launch(
        projectPath: String,
        requestedURL: String?,
        started: Date,
        completion: @escaping (Result<(url: String, owned: Bool, pid: Int32?, startupMS: Double), Error>) -> Void
    ) {
        guard let plan = DevServerPlan.detect(projectPath: projectPath) else {
            completion(.failure(Self.error("未识别前端开发服务器：请在 package.json 配置 dev/start/serve/preview 脚本")))
            return
        }
        if let configured = plan.configuredURL, !BrowserURLPolicy.isAllowed(configured) {
            completion(.failure(Self.error("开发服务器 URL 不是受允许的 localhost 地址")))
            return
        }
        let task = Process()
        let output = Pipe()
        let errorPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = plan.command
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        task.environment = BrowserProcessEnvironment.merged()
        task.standardOutput = output
        task.standardError = errorPipe
        process = task
        ownedProcess = true
        lastOutput = ""
        lastError = nil
        var finished = false
        var detectedURL: String? = requestedURL ?? plan.configuredURL
        let complete: (Result<(url: String, owned: Bool, pid: Int32?, startupMS: Double), Error>) -> Void = { [weak self] result in
            guard !finished else { return }
            finished = true
            completion(result)
            if case .failure = result { self?.stop() }
        }
        func consume(_ data: Data, isError: Bool) {
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if isError { self.lastError = String(BrowserVerificationRedaction.text(String((self.lastError ?? "") + text)).suffix(4_000)) }
            else { self.lastOutput = String(BrowserVerificationRedaction.text(String((self.lastOutput + text).suffix(4_000))) ) }
            if detectedURL == nil { detectedURL = Self.findLocalURL(in: self.lastOutput + "\n" + (self.lastError ?? "")) }
            if let detectedURL, BrowserURLPolicy.isAllowed(detectedURL) {
                complete(.success((BrowserURLPolicy.sanitizedString(detectedURL), true, task.processIdentifier, Date().timeIntervalSince(started) * 1000)))
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in consume(handle.availableData, isError: false) }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in consume(handle.availableData, isError: true) }
        task.terminationHandler = { [weak self] finishedTask in
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            let tail = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorTail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !tail.isEmpty { self?.lastOutput = String(BrowserVerificationRedaction.text(String((self?.lastOutput ?? "") + tail)).suffix(4_000)) }
            if !errorTail.isEmpty { self?.lastError = String(BrowserVerificationRedaction.text(String((self?.lastError ?? "") + errorTail)).suffix(4_000)) }
            guard !finished else { return }
            complete(.failure(Self.error("开发服务器退出（\(finishedTask.terminationStatus)）：\(BrowserVerificationRedaction.text(String((self?.lastError ?? self?.lastOutput ?? "").suffix(800))) )")))
        }
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(BrowserVerificationConfiguration.serverStartupTimeout)
            pollUntilReady(task: task, deadline: deadline, configuredURL: detectedURL, started: started, completion: complete)
        } catch {
            complete(.failure(error))
        }
    }

    private func pollUntilReady(
        task: Process,
        deadline: Date,
        configuredURL: String?,
        started: Date,
        completion: @escaping (Result<(url: String, owned: Bool, pid: Int32?, startupMS: Double), Error>) -> Void
    ) {
        if let configuredURL, BrowserURLPolicy.isAllowed(configuredURL) {
            probe(url: URL(string: configuredURL)!) { [weak self] available in
                guard let self else { return }
                if available {
                    completion(.success((BrowserURLPolicy.sanitizedString(configuredURL), true, task.processIdentifier, Date().timeIntervalSince(started) * 1000)))
                } else if Date() >= deadline || !task.isRunning {
                    completion(.failure(Self.error("开发服务器未在超时时间内就绪")))
                } else {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.pollUntilReady(task: task, deadline: deadline, configuredURL: configuredURL, started: started, completion: completion)
                    }
                }
            }
            return
        }
        let output = lastOutput + "\n" + (lastError ?? "")
        if let found = Self.findLocalURL(in: output) {
            probe(url: URL(string: found)!) { [weak self] available in
                guard let self else { return }
                if available {
                    completion(.success((BrowserURLPolicy.sanitizedString(found), true, task.processIdentifier, Date().timeIntervalSince(started) * 1000)))
                } else if Date() >= deadline || !task.isRunning {
                    completion(.failure(Self.error("开发服务器 URL 不可访问")))
                } else {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.pollUntilReady(task: task, deadline: deadline, configuredURL: nil, started: started, completion: completion)
                    }
                }
            }
        } else if Date() >= deadline || !task.isRunning {
            completion(.failure(Self.error("未能从开发服务器输出检测到 localhost URL")))
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.pollUntilReady(task: task, deadline: deadline, configuredURL: nil, started: started, completion: completion)
            }
        }
    }

    private func probe(url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse).map { (200..<500).contains($0.statusCode) } ?? false)
        }.resume()
    }

    private static func findLocalURL(in text: String) -> String? {
        let pattern = #"https?://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})(?:/[^\s\"'<>]*)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range).flatMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func error(_ description: String) -> NSError {
        NSError(domain: "BrowserVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

// MARK: - 可替换 BrowserDriver

protocol BrowserDriver: AnyObject {
    var runtimeName: String { get }
    var processIdentifier: Int32? { get }
    func launch(completion: @escaping (Result<Void, Error>) -> Void)
    func close()
    func setViewport(_ viewport: BrowserViewport)
    func open(url: URL, completion: @escaping (Result<BrowserInspection, Error>) -> Void)
    func captureScreenshot(fullPage: Bool, completion: @escaping (Result<Data, Error>) -> Void)
}

struct BrowserInspection: Codable, Equatable {
    let title: String
    let url: String
    let viewport: BrowserViewport
    let visibleTextSummary: String
    let interactiveElementCount: Int
    let buttons: [String]
    let links: [String]
    let inputs: [String]
    let forms: Int
    let landmarks: [String]
    let overflowElements: [String]
    let consoleMessages: [String]
    let consoleWarnings: [String]
    let pageErrors: [String]
    let failedRequests: [String]
    let layoutFindings: [BrowserFinding]
    let instrumentationInstalled: Bool
}

final class WKBrowserDriver: NSObject, BrowserDriver, WKNavigationDelegate, WKScriptMessageHandler {
    let runtimeName = "macOS WebKit"
    var processIdentifier: Int32? { nil }

    private var webView: WKWebView?
    private var openCompletion: ((Result<BrowserInspection, Error>) -> Void)?
    private var consoleMessages: [String] = []
    private var consoleWarnings: [String] = []
    private var pageErrors: [String] = []
    private var failedRequests: [String] = []
    private var viewport = BrowserViewport.desktop
    private var loadTimer: DispatchWorkItem?
    private var launchTimer: DispatchWorkItem?

    func launch(completion: @escaping (Result<Void, Error>) -> Void) {
        var completed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard !completed else { return }
            completed = true
            self?.launchTimer = nil
            completion(.failure(Self.error("浏览器启动超时（\(Int(BrowserVerificationConfiguration.browserLaunchTimeout)) 秒）")))
        }
        launchTimer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + BrowserVerificationConfiguration.browserLaunchTimeout, execute: timeout)
        DispatchQueue.main.async {
            guard !completed else { return }
            let configuration = WKWebViewConfiguration()
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(source: Self.instrumentationScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            controller.add(self, name: "aiDevOneBrowserEvidence")
            configuration.userContentController = controller
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: self.viewport.width, height: self.viewport.height), configuration: configuration)
            view.navigationDelegate = self
            view.setValue(false, forKey: "drawsBackground")
            self.webView = view
            completed = true
            self.launchTimer?.cancel()
            self.launchTimer = nil
            completion(.success(()))
        }
    }

    func close() {
        launchTimer?.cancel()
        launchTimer = nil
        loadTimer?.cancel()
        loadTimer = nil
        openCompletion = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "aiDevOneBrowserEvidence")
        webView = nil
    }

    func setViewport(_ viewport: BrowserViewport) {
        self.viewport = viewport
        webView?.setFrameSize(NSSize(width: viewport.width, height: viewport.height))
    }

    func open(url: URL, completion: @escaping (Result<BrowserInspection, Error>) -> Void) {
        guard let webView else {
            completion(.failure(Self.error("浏览器尚未启动")))
            return
        }
        guard BrowserURLPolicy.isAllowed(url.absoluteString) else {
            completion(.failure(Self.error("只允许打开 AI Dev One 自己确认的 localhost 页面")))
            return
        }
        consoleMessages.removeAll(); consoleWarnings.removeAll(); pageErrors.removeAll(); failedRequests.removeAll()
        openCompletion = completion
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let completion = self.openCompletion else { return }
            self.openCompletion = nil
            completion(.failure(Self.error("页面加载超时（\(Int(BrowserVerificationConfiguration.pageLoadTimeout)) 秒）")))
        }
        loadTimer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + BrowserVerificationConfiguration.pageLoadTimeout, execute: timeout)
        webView.load(URLRequest(url: url))
    }

    func captureScreenshot(fullPage: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let webView else { completion(.failure(Self.error("浏览器已关闭"))); return }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        if fullPage {
            let contentHeight = webView.enclosingScrollView?.documentView?.bounds.height ?? webView.bounds.height
            let height = max(webView.bounds.height, contentHeight)
            configuration.rect = NSRect(x: 0, y: 0, width: webView.bounds.width, height: height)
        } else {
            configuration.rect = webView.bounds
        }
        webView.takeSnapshot(with: configuration) { image, error in
            if let error { completion(.failure(error)); return }
            guard let image, let data = image.pngData else {
                completion(.failure(Self.error("无法生成页面截图")))
                return
            }
            completion(.success(data))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let value = Self.redact(String(describing: body["message"] ?? ""))
        switch type {
        case "console.error": consoleMessages.append(value)
        case "console.warn": consoleWarnings.append(value)
        case "page.error": pageErrors.append(value)
        case "network.failure": failedRequests.append(Self.redact(String(describing: body["url"] ?? value)))
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadTimer?.cancel(); loadTimer = nil
        let script = Self.inspectionScript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            webView.evaluateJavaScript(script) { [weak self] object, error in
            guard let self else { return }
            if let error {
                self.openCompletion?(.failure(error)); self.openCompletion = nil; return
            }
            guard let dictionary = object as? [String: Any] else {
                self.openCompletion?(.failure(Self.error("页面 DOM 检查返回格式无效"))); self.openCompletion = nil; return
            }
            let inspection = self.makeInspection(dictionary)
            self.openCompletion?(.success(inspection)); self.openCompletion = nil
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadTimer?.cancel(); loadTimer = nil
        pageErrors.append(Self.redact(error.localizedDescription))
        openCompletion?(.failure(error)); openCompletion = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadTimer?.cancel(); loadTimer = nil
        pageErrors.append(Self.redact(error.localizedDescription))
        openCompletion?(.failure(error)); openCompletion = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = Self.error("浏览器页面进程已退出")
        openCompletion?(.failure(error)); openCompletion = nil
    }

    private func makeInspection(_ value: [String: Any]) -> BrowserInspection {
        let layout = value["layout"] as? [String: Any] ?? [:]
        let evidence = value["evidence"] as? [String: Any] ?? [:]
        let evaluatedErrors = Self.strings(evidence["errors"], limit: 50)
        let evaluatedWarnings = Self.strings(evidence["warnings"], limit: 50)
        let evaluatedPageErrors = Self.strings(evidence["pageErrors"], limit: 50)
        let evaluatedNetworkFailures = Self.strings(evidence["networkFailures"], limit: 50)
        let overflow = (layout["overflowElements"] as? [String] ?? []).prefix(30)
        let findings = Self.layoutFindings(layout)
        return BrowserInspection(
            title: Self.string(value["title"]),
            url: BrowserURLPolicy.sanitizedString(Self.string(value["url"])),
            viewport: BrowserViewport(width: Self.int(value["viewportWidth"], fallback: viewport.width), height: Self.int(value["viewportHeight"], fallback: viewport.height)),
            visibleTextSummary: Self.redact(Self.string(value["visibleTextSummary"])).prefix(1_200).description,
            interactiveElementCount: Self.int(value["interactiveElementCount"]),
            buttons: Self.strings(value["buttons"], limit: 30),
            links: Self.strings(value["links"], limit: 30),
            inputs: Self.strings(value["inputs"], limit: 30),
            forms: Self.int(value["forms"]),
            landmarks: Self.strings(value["landmarks"], limit: 20),
            overflowElements: Array(overflow),
            consoleMessages: Array(Set(consoleMessages + evaluatedErrors)).prefix(50).map { $0 },
            consoleWarnings: Array(Set(consoleWarnings + evaluatedWarnings)).prefix(50).map { $0 },
            pageErrors: Array(Set(pageErrors + evaluatedPageErrors)).prefix(50).map { $0 },
            failedRequests: Array(Set(failedRequests + evaluatedNetworkFailures)).prefix(50).map { $0 },
            layoutFindings: findings,
            instrumentationInstalled: (value["instrumentationInstalled"] as? NSNumber)?.boolValue ?? false
        )
    }

    private static func layoutFindings(_ layout: [String: Any]) -> [BrowserFinding] {
        var result: [BrowserFinding] = []
        if bool(layout["horizontalOverflow"]) {
            result.append(BrowserFinding(code: "horizontal_overflow", severity: .error, message: "页面存在横向溢出", detail: "document.scrollWidth 大于 viewport"))
        }
        if bool(layout["verticalOverflow"]) {
            result.append(BrowserFinding(code: "vertical_overflow", severity: .warning, message: "页面存在纵向滚动区域", detail: nil))
        }
        for element in (layout["invalidImportantElements"] as? [[String: Any]] ?? []).prefix(20) {
            let name = string(element["name"])
            let reason = string(element["reason"])
            result.append(BrowserFinding(code: "important_element_\(reason)", severity: .error, message: "重要控件不可用：\(name)", detail: reason))
        }
        for overlap in (layout["overlaps"] as? [[String: Any]] ?? []).prefix(20) {
            result.append(BrowserFinding(code: "overlap", severity: .error, message: "重要控件发生重叠", detail: "\(string(overlap["first"])) / \(string(overlap["second"]))"))
        }
        return result
    }

    private static let instrumentationScript = #"""
    (() => {
      if (window.__aiDevOneEvidenceInstalled) return;
      window.__aiDevOneEvidenceInstalled = true;
      window.__aiDevOneEvidence = {errors: [], warnings: [], pageErrors: [], networkFailures: []};
      const send = (type, payload) => {
        const value = String((payload && (payload.message || payload.url)) || '').slice(0, 1000);
        if (type === 'console.error') window.__aiDevOneEvidence.errors.push(value);
        if (type === 'console.warn') window.__aiDevOneEvidence.warnings.push(value);
        if (type === 'page.error') window.__aiDevOneEvidence.pageErrors.push(value);
        if (type === 'network.failure') window.__aiDevOneEvidence.networkFailures.push(value);
        try { window.webkit.messageHandlers.aiDevOneBrowserEvidence.postMessage(Object.assign({type}, payload || {})); } catch (_) {}
      };
      const originalError = console.error.bind(console);
      const originalWarn = console.warn.bind(console);
      console.error = (...args) => { send('console.error', {message: args.map(String).join(' ').slice(0, 800)}); originalError(...args); };
      console.warn = (...args) => { send('console.warn', {message: args.map(String).join(' ').slice(0, 800)}); originalWarn(...args); };
      window.addEventListener('error', event => send('page.error', {message: String(event.message || 'uncaught error').slice(0, 800)}));
      window.addEventListener('unhandledrejection', event => send('page.error', {message: String(event.reason || 'unhandled rejection').slice(0, 800)}));
      const originalFetch = window.fetch;
      window.fetch = (...args) => originalFetch(...args).then(response => { if (!response.ok) send('network.failure', {url: String(response.url || args[0])}); return response; }).catch(error => { send('network.failure', {url: String(args[0] || error)}); throw error; });
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) { this.__aiDevOneURL = String(url); return originalOpen.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function() { this.addEventListener('load', () => { if (this.status >= 400) send('network.failure', {url: this.__aiDevOneURL}); }); this.addEventListener('error', () => send('network.failure', {url: this.__aiDevOneURL})); return originalSend.apply(this, arguments); };
    })();
    """#

    private static let inspectionScript = #"""
    (() => {
      const visible = el => { const s = getComputedStyle(el), r = el.getBoundingClientRect(); return s.display !== 'none' && s.visibility !== 'hidden' && parseFloat(s.opacity || '1') > 0 && r.width > 0 && r.height > 0; };
      const label = el => (el.getAttribute('aria-label') || el.getAttribute('name') || el.innerText || el.textContent || el.tagName || '').trim().replace(/\s+/g, ' ').slice(0, 120);
      const all = selector => Array.from(document.querySelectorAll(selector));
      const interactive = all('button,a,input,select,textarea,[role="button"],[tabindex]');
      const important = all('button,[role="button"],input[type="submit"],input[type="button"],nav,main,header,footer').filter(visible);
      const invalidImportantElements = important.map(el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el); let reason = ''; if (r.width <= 0 || r.height <= 0) reason = 'zero_size'; else if (r.right < 0 || r.left > innerWidth || r.bottom < 0 || r.top > innerHeight) reason = 'offscreen'; else if (s.display === 'none' || s.visibility === 'hidden') reason = 'hidden'; return reason ? {name: label(el), reason} : null; }).filter(Boolean);
      const rects = important.filter(el => ['BUTTON','INPUT','TEXTAREA'].includes(el.tagName)).map(el => ({name: label(el), r: el.getBoundingClientRect()}));
      const overlaps = []; for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) { const a=rects[i].r,b=rects[j].r; const area=Math.max(0, Math.min(a.right,b.right)-Math.max(a.left,b.left))*Math.max(0, Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)); if (area > 8) overlaps.push({first:rects[i].name,second:rects[j].name}); }
      const overflowElements = all('*').filter(el => { const r=el.getBoundingClientRect(); return r.right > innerWidth + 1 || r.left < -1; }).slice(0, 30).map(label);
      const visibleTextSummary = (document.body?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 1600);
      const landmarks = all('main,nav,header,footer,aside,section,form').filter(visible).map(label).slice(0, 20);
      return {title: document.title || '', url: location.href, viewportWidth: innerWidth, viewportHeight: innerHeight, visibleTextSummary, interactiveElementCount: interactive.length, buttons: all('button').filter(visible).map(label).slice(0,30), links: all('a').filter(visible).map(label).slice(0,30), inputs: all('input,textarea,select').filter(visible).map(label).slice(0,30), forms: all('form').length, landmarks, instrumentationInstalled: !!window.__aiDevOneEvidenceInstalled, evidence: window.__aiDevOneEvidence || {}, layout: {horizontalOverflow: document.documentElement.scrollWidth > innerWidth + 1 || document.body.scrollWidth > innerWidth + 1, verticalOverflow: document.documentElement.scrollHeight > innerHeight + 1, overflowElements, invalidImportantElements, overlaps}};
    })()
    """#

    private static func string(_ value: Any?) -> String { value as? String ?? "" }
    private static func int(_ value: Any?, fallback: Int = 0) -> Int { (value as? NSNumber)?.intValue ?? fallback }
    private static func bool(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? (value as? Bool ?? false) }
    private static func strings(_ value: Any?, limit: Int) -> [String] { Array((value as? [String] ?? []).prefix(limit)) }
    private static func redact(_ value: String) -> String {
        String(BrowserVerificationRedaction.text(value).prefix(1_000))
    }
    private static func error(_ description: String) -> NSError { NSError(domain: "BrowserVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: description]) }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Evidence storage and orchestration

enum BrowserEvidenceStore {
    static var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support.appendingPathComponent("Nexus", isDirectory: true)
        let base = FileManager.default.fileExists(atPath: legacy.path)
            ? legacy
            : support.appendingPathComponent("AI Dev One", isDirectory: true)
        let root = base.appendingPathComponent("browser-verification", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func directory(taskID: String?, verificationID: String) -> URL {
        let task = taskID?.isEmpty == false ? taskID! : "unassigned"
        let url = rootURL.appendingPathComponent(task, isDirectory: true).appendingPathComponent(verificationID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ data: Data, name: String, directory: URL) -> (path: String, sha256: String)? {
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return (url.path, digest(data))
        } catch { return nil }
    }

    static func saveResult(_ result: BrowserVerificationResult, directory: URL) {
        guard let data = try? JSONEncoder.iso8601.encode(result) else { return }
        try? data.write(to: directory.appendingPathComponent("result.json"), options: .atomic)
    }

    static func cleanup(taskID: String) {
        let url = rootURL.appendingPathComponent(taskID, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanupExpired(now: Date = Date()) {
        guard let tasks = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        for task in tasks {
            let date = (try? task.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(date) > BrowserVerificationConfiguration.artifactRetention {
                try? FileManager.default.removeItem(at: task)
            }
        }
    }

    private static func digest(_ data: Data) -> String {
        #if canImport(CryptoKit)
        importCryptoKitWorkaround(data)
        #else
        var value: UInt64 = 14695981039346656037
        for byte in data { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return String(format: "%016llx", value)
        #endif
    }

    #if canImport(CryptoKit)
    private static func importCryptoKitWorkaround(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }
}

final class BrowserVerificationService {
    static let shared = BrowserVerificationService()
    private var server: DevServerSupervisor?
    private var driver: BrowserDriver?
    private(set) var activeSession: BrowserVerificationSession?
    private var completion: ((BrowserVerificationResult) -> Void)?
    private var cancelled = false
    private var verificationTimer: DispatchWorkItem?

    func verify(
        projectPath: String,
        taskID: String? = nil,
        projectID: String? = nil,
        requestedURL: String? = nil,
        viewport: BrowserViewport = .desktop,
        completion: @escaping (BrowserVerificationResult) -> Void
    ) {
        guard activeSession == nil else {
            completion(Self.errorResult(projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, message: "已有浏览器验证正在运行"))
            return
        }
        BrowserEvidenceStore.cleanupExpired()
        let verificationID = UUID().uuidString.lowercased()
        guard let runtime = BrowserRuntimeInfo.detect() else {
            completion(Self.skippedResult(projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, reason: "未检测到浏览器运行环境"))
            return
        }
        let plan = DevServerPlan.detect(projectPath: projectPath)
        guard plan != nil else {
            completion(Self.skippedResult(projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, reason: "项目未识别到本地前端开发服务器"))
            return
        }
        if let requestedURL, !BrowserURLPolicy.isAllowed(requestedURL) {
            completion(Self.errorResult(projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, message: "外部 URL 被禁止；浏览器验证只允许 localhost"))
            return
        }
        let session = BrowserVerificationSession(verificationID: verificationID, taskID: taskID, projectID: projectID, projectPath: projectPath, devServerCommand: plan?.displayCommand, devServerPID: nil, devServerURL: nil, browserRuntime: runtime.name, browserPID: nil, startedAt: Date(), endedAt: nil, viewport: viewport, status: .startingServer)
        activeSession = session
        self.completion = completion
        cancelled = false
        let verificationTimeout = DispatchWorkItem { [weak self] in
            guard let self, let active = self.activeSession else { return }
            self.finish(status: .error, projectPath: active.projectPath, taskID: active.taskID, projectID: active.projectID, viewport: active.viewport, url: active.devServerURL, serverPID: active.devServerPID, browserRuntime: active.browserRuntime, serverStartMS: 0, error: "浏览器验证超时（\(Int(BrowserVerificationConfiguration.verificationTimeout)) 秒）")
        }
        verificationTimer = verificationTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + BrowserVerificationConfiguration.verificationTimeout, execute: verificationTimeout)
        server = DevServerSupervisor()
        let start = Date()
        server?.start(projectPath: projectPath, requestedURL: requestedURL) { [weak self] serverResult in
            DispatchQueue.main.async {
                guard let self, self.activeSession?.verificationID == verificationID else { return }
                switch serverResult {
                case .failure(let error): self.finish(status: .error, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: nil, serverPID: self.server?.pid, browserRuntime: runtime.name, serverStartMS: Date().timeIntervalSince(start) * 1000, error: error.localizedDescription)
                case .success(let info):
                    self.updateSession(status: .launchingBrowser, serverURL: info.url, serverPID: info.pid)
                    let driver = WKBrowserDriver(); self.driver = driver
                    driver.launch { launchResult in
                        DispatchQueue.main.async {
                            guard self.activeSession?.verificationID == verificationID else { return }
                            switch launchResult {
                            case .failure(let error): self.finish(status: .error, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: info.url, serverPID: info.pid, browserRuntime: runtime.name, serverStartMS: info.startupMS, error: error.localizedDescription)
                            case .success:
                                driver.setViewport(viewport); self.updateSession(status: .loadingPage, serverURL: info.url, serverPID: info.pid)
                                guard let url = URL(string: info.url) else { self.finish(status: .error, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: info.url, serverPID: info.pid, browserRuntime: runtime.name, serverStartMS: info.startupMS, error: "检测到的 URL 无效"); return }
                                let pageAndDOMStarted = Date()
                                driver.open(url: url) { inspectionResult in
                                    DispatchQueue.main.async {
                                        guard self.activeSession?.verificationID == verificationID else { return }
                                        let pageAndDOMMS = Date().timeIntervalSince(pageAndDOMStarted) * 1000
                                        switch inspectionResult {
                                        case .failure(let error):
                                            let serverDetail = BrowserVerificationRedaction.text([self.server?.lastError, self.server?.lastOutput].compactMap { $0 }.joined(separator: " "))
                                            self.finish(status: .error, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: info.url, serverPID: info.pid, browserRuntime: runtime.name, serverStartMS: info.startupMS, error: [error.localizedDescription, serverDetail].filter { !$0.isEmpty }.joined(separator: " — "))
                                        case .success(let inspection): self.captureEvidence(inspection: inspection, pageAndDOMMS: pageAndDOMMS, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: info.url, serverPID: info.pid, browserRuntime: runtime.name, serverStartMS: info.startupMS)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        guard activeSession != nil else { return }
        cancelled = true
        driver?.close(); driver = nil
        if let session = activeSession {
            finish(status: .cancelled, projectPath: session.projectPath, taskID: session.taskID, projectID: session.projectID, viewport: session.viewport, url: session.devServerURL, serverPID: session.devServerPID, browserRuntime: session.browserRuntime, serverStartMS: 0, error: "浏览器验证已取消")
        }
    }

    private func captureEvidence(inspection: BrowserInspection, pageAndDOMMS: Double, projectPath: String, taskID: String?, projectID: String?, viewport: BrowserViewport, url: String, serverPID: Int32?, browserRuntime: String, serverStartMS: Double) {
        guard !cancelled else { return }
        updateSession(status: .capturing, serverURL: url, serverPID: serverPID)
        let directory = BrowserEvidenceStore.directory(taskID: taskID, verificationID: activeSession?.verificationID ?? UUID().uuidString.lowercased())
        let screenshotStarted = Date()
        driver?.captureScreenshot(fullPage: false) { [weak self] shot in
            DispatchQueue.main.async {
                guard let self else { return }
                let screenshotMS = Date().timeIntervalSince(screenshotStarted) * 1000
                let artifacts: [BrowserScreenshotArtifact]
                switch shot {
                case .failure:
                    artifacts = []
                case .success(let data):
                    if let saved = BrowserEvidenceStore.save(data, name: "viewport.png", directory: directory) {
                        artifacts = [BrowserScreenshotArtifact(kind: "viewport", path: saved.path, sha256: saved.sha256, width: viewport.width, height: viewport.height)]
                    } else { artifacts = [] }
                }
                self.finishInspection(inspection, artifacts: artifacts, pageAndDOMMS: pageAndDOMMS, screenshotMS: screenshotMS, directory: directory, projectPath: projectPath, taskID: taskID, projectID: projectID, viewport: viewport, url: url, serverPID: serverPID, browserRuntime: browserRuntime, serverStartMS: serverStartMS)
            }
        }
    }

    private func finishInspection(_ inspection: BrowserInspection, artifacts: [BrowserScreenshotArtifact], pageAndDOMMS: Double, screenshotMS: Double, directory: URL, projectPath: String, taskID: String?, projectID: String?, viewport: BrowserViewport, url: String, serverPID: Int32?, browserRuntime: String, serverStartMS: Double) {
        updateSession(status: .analyzing, serverURL: url, serverPID: serverPID)
        var findings = inspection.layoutFindings
        findings.append(contentsOf: inspection.consoleMessages.map { BrowserFinding(code: "console_error", severity: .error, message: "页面 console.error", detail: $0) })
        findings.append(contentsOf: inspection.pageErrors.map { BrowserFinding(code: "page_error", severity: .critical, message: "页面运行时错误", detail: $0) })
        findings.append(contentsOf: inspection.failedRequests.map { BrowserFinding(code: "network_failure", severity: .error, message: "资源请求失败", detail: BrowserURLPolicy.sanitizedString($0)) })
        let status: BrowserVerificationStatus = findings.contains { $0.severity == .error || $0.severity == .critical } ? .failed : .passed
        let summary = status == .passed
            ? "页面加载、DOM、Console、Network 和布局检查均通过。"
            : "发现 \(findings.count) 个需要处理的问题。"
        let endedAt = Date()
        let startedAt = activeSession?.startedAt ?? endedAt
        finishResult(BrowserVerificationResult(verificationID: activeSession?.verificationID ?? UUID().uuidString.lowercased(), taskID: taskID, projectID: projectID, projectPath: projectPath, devServerCommand: activeSession?.devServerCommand, devServerPID: serverPID, devServerURL: BrowserURLPolicy.sanitizedString(url), browserRuntime: browserRuntime, browserPID: nil, startedAt: startedAt, endedAt: endedAt, viewport: viewport, status: status, screenshots: artifacts, consoleMessages: inspection.consoleMessages, consoleWarnings: inspection.consoleWarnings, pageErrors: inspection.pageErrors, failedRequests: inspection.failedRequests.map(BrowserURLPolicy.sanitizedString), layoutFindings: inspection.layoutFindings, findings: findings, instrumentationInstalled: inspection.instrumentationInstalled, timingsMS: ["devServerStartup": serverStartMS, "pageAndDOM": pageAndDOMMS, "screenshot": screenshotMS, "total": endedAt.timeIntervalSince(startedAt) * 1000], summary: summary), directory: directory)
    }

    private func finish(status: BrowserVerificationStatus, projectPath: String, taskID: String?, projectID: String?, viewport: BrowserViewport, url: String?, serverPID: Int32?, browserRuntime: String, serverStartMS: Double, error: String) {
        let directory = BrowserEvidenceStore.directory(taskID: taskID, verificationID: activeSession?.verificationID ?? UUID().uuidString.lowercased())
        let safeError = BrowserVerificationRedaction.text(error)
        let finding = BrowserFinding(code: "verification_error", severity: status == .cancelled ? .warning : .critical, message: safeError, detail: nil)
        let endedAt = Date()
        let startedAt = activeSession?.startedAt ?? endedAt
        finishResult(BrowserVerificationResult(verificationID: activeSession?.verificationID ?? UUID().uuidString.lowercased(), taskID: taskID, projectID: projectID, projectPath: projectPath, devServerCommand: activeSession?.devServerCommand, devServerPID: serverPID, devServerURL: url.map(BrowserURLPolicy.sanitizedString), browserRuntime: browserRuntime, browserPID: nil, startedAt: startedAt, endedAt: endedAt, viewport: viewport, status: status, screenshots: [], consoleMessages: [], consoleWarnings: [], pageErrors: [], failedRequests: [], layoutFindings: [], findings: [finding], instrumentationInstalled: false, timingsMS: ["devServerStartup": serverStartMS, "total": endedAt.timeIntervalSince(startedAt) * 1000], summary: safeError), directory: directory)
    }

    private func finishResult(_ result: BrowserVerificationResult, directory: URL) {
        verificationTimer?.cancel()
        verificationTimer = nil
        BrowserEvidenceStore.saveResult(result, directory: directory)
        driver?.close(); driver = nil
        let finishedServer = server
        server = nil
        activeSession = nil
        let callback = completion
        completion = nil
        // Drain the owned npm/node tree before exposing completion. This
        // prevents a subsequent verification from racing a still-bound port.
        finishedServer?.stop {
            callback?(result)
        }
    }

    private func updateSession(status: BrowserVerificationStatus, serverURL: String?, serverPID: Int32?) {
        guard var session = activeSession else { return }
        session.status = status; session.devServerURL = serverURL; session.devServerPID = serverPID
        activeSession = session
    }

    private static func skippedResult(projectPath: String, taskID: String?, projectID: String?, viewport: BrowserViewport, reason: String) -> BrowserVerificationResult {
        BrowserVerificationResult(verificationID: UUID().uuidString.lowercased(), taskID: taskID, projectID: projectID, projectPath: projectPath, devServerCommand: nil, devServerPID: nil, devServerURL: nil, browserRuntime: "unavailable", browserPID: nil, startedAt: Date(), endedAt: Date(), viewport: viewport, status: .skipped, screenshots: [], consoleMessages: [], consoleWarnings: [], pageErrors: [], failedRequests: [], layoutFindings: [], findings: [BrowserFinding(code: "runtime_unavailable", severity: .warning, message: reason, detail: "请配置本机浏览器运行环境后重试")], instrumentationInstalled: false, timingsMS: [:], summary: reason)
    }

    private static func errorResult(projectPath: String, taskID: String?, projectID: String?, viewport: BrowserViewport, message: String) -> BrowserVerificationResult {
        BrowserVerificationResult(verificationID: UUID().uuidString.lowercased(), taskID: taskID, projectID: projectID, projectPath: projectPath, devServerCommand: nil, devServerPID: nil, devServerURL: nil, browserRuntime: "macOS WebKit", browserPID: nil, startedAt: Date(), endedAt: Date(), viewport: viewport, status: .error, screenshots: [], consoleMessages: [], consoleWarnings: [], pageErrors: [], failedRequests: [], layoutFindings: [], findings: [BrowserFinding(code: "verification_error", severity: .critical, message: message, detail: nil)], instrumentationInstalled: false, timingsMS: [:], summary: message)
    }
}
