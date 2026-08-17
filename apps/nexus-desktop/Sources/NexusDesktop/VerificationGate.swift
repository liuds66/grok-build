import Foundation

enum VerificationStatus: String, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case skipped = "SKIPPED"
}

struct VerificationCheck: Codable, Equatable {
    let name: String
    let command: String?
    let status: VerificationStatus
    let reason: String?
    let output: String?
    let duration: TimeInterval
}

struct VerificationReport: Codable, Equatable {
    let projectPath: String
    let checks: [VerificationCheck]

    var hasFailure: Bool { checks.contains { $0.status == .fail } }
    var passed: Bool { !hasFailure && !checks.isEmpty }
}

/// Runs only known, project-local verification commands. Missing tools and
/// missing scripts are explicit SKIPPED results, never false failures.
enum VerificationGate {
    private struct PlannedCheck {
        let name: String
        let command: [String]?
        let displayCommand: String?
        let reason: String?
    }

    static func evaluate(projectPath: String, timeout: TimeInterval = 120) -> VerificationReport {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let plan = makePlan(projectURL: projectURL)
        let checks = plan.map { planned in
            guard planned.command != nil else {
                return VerificationCheck(
                    name: planned.name,
                    command: planned.displayCommand,
                    status: .skipped,
                    reason: planned.reason ?? "项目未配置此检查",
                    output: nil,
                    duration: 0
                )
            }
            return run(planned, in: projectURL, timeout: timeout)
        }
        return VerificationReport(projectPath: projectURL.path, checks: checks)
    }

    static func evaluateAsync(
        projectPath: String,
        timeout: TimeInterval = 120,
        completion: @escaping (VerificationReport) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let report = evaluate(projectPath: projectPath, timeout: timeout)
            DispatchQueue.main.async { completion(report) }
        }
    }

    static func plannedChecks(projectPath: String) -> [(String, String?, String?)] {
        makePlan(projectURL: URL(fileURLWithPath: projectPath, isDirectory: true))
            .map { ($0.name, $0.displayCommand, $0.reason) }
    }

    private static func makePlan(projectURL: URL) -> [PlannedCheck] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectURL.path) else {
            return [PlannedCheck(name: "项目检查", command: nil, displayCommand: nil, reason: "项目目录不存在")]
        }

        if let packageURL = projectURL.appendingPathComponent("package.json") as URL?,
           let data = try? Data(contentsOf: packageURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any] {
            return ["typecheck", "lint", "test", "build"].map { name in
                guard scripts[name] != nil else {
                    return PlannedCheck(name: "Node \(name)", command: nil, displayCommand: "npm run \(name)", reason: "package.json 未定义脚本")
                }
                guard executable(named: "npm") else {
                    return PlannedCheck(name: "Node \(name)", command: nil, displayCommand: "npm run \(name)", reason: "未找到 npm")
                }
                return PlannedCheck(name: "Node \(name)", command: ["npm", "run", name], displayCommand: "npm run \(name)", reason: nil)
            }
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) {
            return [
                ("Rust fmt", ["cargo", "fmt", "--check"], "cargo fmt --check"),
                ("Rust clippy", ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"], "cargo clippy --all-targets --all-features -- -D warnings"),
                ("Rust test", ["cargo", "test"], "cargo test"),
                ("Rust build", ["cargo", "build"], "cargo build"),
            ].map { name, command, display in
                executable(named: "cargo")
                    ? PlannedCheck(name: name, command: command, displayCommand: display, reason: nil)
                    : PlannedCheck(name: name, command: nil, displayCommand: display, reason: "未找到 cargo")
            }
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("pyproject.toml").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("pytest.ini").path)
            || fm.fileExists(atPath: projectURL.appendingPathComponent("requirements.txt").path) {
            return [
                ("Python ruff", ["ruff", "check", "."], "ruff check ."),
                ("Python pytest", ["pytest"], "pytest"),
                ("Python pyright", ["pyright"], "pyright"),
            ].map { name, command, display in
                let executableName = command[0]
                return executable(named: executableName)
                    ? PlannedCheck(name: name, command: command, displayCommand: display, reason: nil)
                    : PlannedCheck(name: name, command: nil, displayCommand: display, reason: "未找到 \(executableName)")
            }
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("go.mod").path) {
            return [
                ("Go fmt", ["gofmt", "-l", "."], "gofmt -l ."),
                ("Go vet", ["go", "vet", "./..."], "go vet ./..."),
                ("Go test", ["go", "test", "./..."], "go test ./..."),
            ].map { name, command, display in
                executable(named: command[0])
                    ? PlannedCheck(name: name, command: command, displayCommand: display, reason: nil)
                    : PlannedCheck(name: name, command: nil, displayCommand: display, reason: "未找到 \(command[0])")
            }
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("platformio.ini").path)
            || (try? fm.contentsOfDirectory(atPath: projectURL.path).contains { $0.hasSuffix(".ino") }) == true {
            return [
                PlannedCheck(name: "Firmware compile", command: nil, displayCommand: nil, reason: "未配置固件编译命令"),
                PlannedCheck(name: "Firmware static checks", command: nil, displayCommand: nil, reason: "未配置固件静态检查命令"),
            ]
        }

        return [PlannedCheck(name: "项目验证", command: nil, displayCommand: nil, reason: "未识别项目类型")]
    }

    private static func executable(named name: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        return path.contains { FileManager.default.isExecutableFile(atPath: String($0) + "/" + name) }
            || ["/usr/bin/\(name)", "/usr/local/bin/\(name)", "/opt/homebrew/bin/\(name)"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ planned: PlannedCheck, in projectURL: URL, timeout: TimeInterval) -> VerificationCheck {
        guard let command = planned.command else {
            return VerificationCheck(name: planned.name, command: planned.displayCommand, status: .skipped, reason: planned.reason, output: nil, duration: 0)
        }
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = projectURL
        var environment = ProcessInfo.processInfo.environment
        environment["GROK_TELEMETRY_ENABLED"] = "0"
        environment["DISABLE_TELEMETRY"] = "1"
        process.environment = environment
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-verification-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try? FileHandle(forWritingTo: outputURL)
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let timedOut = process.isRunning
            if timedOut { process.terminate() }
            process.waitUntilExit()
            try? outputHandle?.close()
            let raw = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: outputURL)
            let output = String(raw.suffix(4000))
            if timedOut {
                return VerificationCheck(name: planned.name, command: planned.displayCommand, status: .fail, reason: "验证超时（\(Int(timeout)) 秒）", output: output, duration: Date().timeIntervalSince(started))
            }
            return VerificationCheck(name: planned.name, command: planned.displayCommand, status: process.terminationStatus == 0 ? .pass : .fail, reason: process.terminationStatus == 0 ? nil : "退出码 \(process.terminationStatus)", output: output, duration: Date().timeIntervalSince(started))
        } catch {
            try? outputHandle?.close()
            try? FileManager.default.removeItem(at: outputURL)
            return VerificationCheck(name: planned.name, command: planned.displayCommand, status: .fail, reason: "无法启动验证：\(error.localizedDescription)", output: nil, duration: Date().timeIntervalSince(started))
        }
    }
}
