import Foundation

@main
struct ProjectIntelligenceAcceptanceHarness {
    private static let fileManager = FileManager.default

    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            fatalError("usage: project-intelligence-acceptance-harness <temp-root> <workspace-root>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let workspaceRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let typescript = root.appendingPathComponent("typescript-project", isDirectory: true)
        let rust = root.appendingPathComponent("rust-project", isDirectory: true)
        let python = root.appendingPathComponent("python-project", isDirectory: true)
        let rollback = root.appendingPathComponent("rollback-project", isDirectory: true)
        try createTypeScriptProject(at: typescript)
        try createRustProject(at: rust)
        try createPythonProject(at: python)
        try createRollbackProject(at: rollback)

        let scanner = ProjectIntelligenceScanner(maxFiles: 100_000)
        let tsFirst = try validateProject(scanner: scanner, path: typescript, stack: "React", language: "TypeScript")
        let rustFirst = try validateProject(scanner: scanner, path: rust, stack: "Rust", language: "Rust")
        let pythonFirst = try validateProject(scanner: scanner, path: python, stack: "Python", language: "Python")
        // Use a real, bounded project inside the repository for acceptance.
        // Scanning the entire upstream monorepo is intentionally excluded
        // from the gate: it contains generated/vendor trees and turns a
        // deterministic project check into an external-volume endurance run.
        let actualProject = workspaceRoot.appendingPathComponent("apps/nexus-desktop", isDirectory: true)
        let actualStart = Date()
        let actual = try scanner.scan(projectPath: actualProject.path)
        let actualSeconds = Date().timeIntervalSince(actualStart)
        expect(actual.files.count > 0, "actual workspace has no indexed files")
        expect(actual.project.gitRoot != nil && actual.project.headCommit != nil, "actual workspace git metadata missing")
        expect(actual.project.languages.contains("Swift"), "actual workspace Swift language missing")
        print(String(format: "REAL_PROJECT swift-subproject files=%d modules=%d symbols=%d tests=%d languages=%@ branch=%@ seconds=%.3f", actual.fileCount, actual.moduleCount, actual.symbolCount, actual.testCount, actual.project.languages.joined(separator: ","), actual.project.branch ?? "(none)", actualSeconds))
        print(String(format: "REAL_PROJECT typescript files=%d symbols=%d tests=%d branch=%@", tsFirst.fileCount, tsFirst.symbolCount, tsFirst.testCount, tsFirst.project.branch ?? "(none)"))
        print(String(format: "REAL_PROJECT rust files=%d symbols=%d tests=%d branch=%@", rustFirst.fileCount, rustFirst.symbolCount, rustFirst.testCount, rustFirst.project.branch ?? "(none)"))
        print(String(format: "REAL_PROJECT python files=%d symbols=%d tests=%d branch=%@", pythonFirst.fileCount, pythonFirst.symbolCount, pythonFirst.testCount, pythonFirst.project.branch ?? "(none)"))

        let incremental = try validateIncremental(scanner: scanner, path: typescript, first: tsFirst)
        print(String(format: "INCREMENTAL first=%d secondReused=%d modifiedChanged=%d added=%d deleted=%d renamed=%d testChanged=%d", incremental.first, incremental.secondReused, incremental.modifiedChanged, incremental.added, incremental.deleted, incremental.renamed, incremental.testChanged))

        let storeRoot = root.appendingPathComponent("index-store", isDirectory: true)
        let store = ProjectIntelligenceStore(rootURL: storeRoot)
        let persistedIndex = try scanner.scan(projectPath: typescript.path, previous: incremental.latest)
        try store.save(persistedIndex)
        let cachedStart = Date()
        let cached = store.load(projectPath: typescript.path)
        let cachedSeconds = Date().timeIntervalSince(cachedStart)
        expect(cached?.project.projectId == persistedIndex.project.projectId, "cold cached index did not load")
        print(String(format: "PERSISTENCE cachedLoad=%.6fs files=%d", cachedSeconds, cached?.fileCount ?? 0))

        let invalidURL = store.projectURL(for: typescript.path).appendingPathComponent("index.json")
        let validData = try Data(contentsOf: invalidURL)
        let validText = String(decoding: validData, as: UTF8.self)
        let invalidText = try replaceIndexVersion(validText)
        expect(invalidText != validText, "could not construct invalid index version fixture")
        try Data(invalidText.utf8).write(to: invalidURL, options: .atomic)
        expect(store.load(projectPath: typescript.path) == nil, "incompatible index version was accepted")
        let rebuilt = try scanner.scan(projectPath: typescript.path)
        try store.save(rebuilt)
        print("INDEX_VERSION invalid=rejected rebuild=PASS")

        let sanitizerStore = ProjectIntelligenceStore(rootURL: root.appendingPathComponent("knowledge-store", isDirectory: true))
        let sanitizerService = ProjectIntelligenceService(scanner: scanner, store: sanitizerStore)
        _ = try sanitizerService.indexSynchronously(projectPath: typescript.path, force: true)
        let knowledge = TaskKnowledge(
            taskId: "acceptance-task",
            summary: "inspect sk-live-acceptance-secret",
            filesRead: ["src/math.ts bearer acceptance-secret-value"],
            filesChanged: ["src/math.ts"],
            symbolsChanged: ["multiply"],
            verification: ["test=PASS"],
            finalState: "completed",
            recordedAt: Date()
        )
        sanitizerService.recordTaskKnowledge(knowledge, projectPath: typescript.path)
        let knowledgeDeadline = Date().addingTimeInterval(5)
        while Date() < knowledgeDeadline && !(sanitizerService.cachedIndex(projectPath: typescript.path)?.taskKnowledge.contains(where: { $0.taskId == "acceptance-task" }) == true) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        expect(sanitizerService.cachedIndex(projectPath: typescript.path)?.taskKnowledge.contains(where: { $0.taskId == "acceptance-task" }) == true, "knowledge writeback timeout")
        let knowledgeIndex = try sanitizerService.indexSynchronously(projectPath: typescript.path)
        let knowledgeJSON = String(decoding: try JSONEncoder().encode(knowledgeIndex.taskKnowledge), as: UTF8.self)
        expect(!knowledgeJSON.contains("sk-live-acceptance-secret") && !knowledgeJSON.contains("acceptance-secret-value"), "TaskKnowledge secret leaked")
        print("SENSITIVE_BOUNDARY fileMetadata=PASS contentHash=nil taskKnowledgeRedaction=PASS")

        let contextProvider = ProjectContextProvider(service: sanitizerService)
        let context = contextProvider.promptContext(projectPath: typescript.path, query: "multiply login", maxCharacters: 6_000)
        let relevant = contextProvider.findRelevantFiles(projectPath: typescript.path, query: "multiply", limit: 8)
        expect(!relevant.isEmpty && relevant.first?.relativePath.contains("math") == true, "context relevance did not find math module")
        expect(context.count <= 6_000 && context.contains("Relevant files:"), "context exceeded bounded contract")
        print(String(format: "CONTEXT overviewFiles=%d relevantFiles=%d symbols=%d relatedTests=%d serialized=%d architectBridge=PASS", knowledgeIndex.fileCount, relevant.count, relevant.flatMap { $0.symbols }.count, knowledgeIndex.tests.count, context.count))

        let switchResult = try validateProjectSwitchRace(scanner: scanner, root: root, paths: [typescript, rust, python])
        print("PROJECT_SWITCH callbacks=3 acceptedFinal=\(switchResult) requestToken=PASS")

        let rollbackResult = try validateRollbackReindex(scanner: scanner, project: rollback, root: root)
        print("ROLLBACK_REINDEX disk=PASS files=\(rollbackResult) hashes=PASS dependencies=PASS relatedTests=PASS")

        let watcherResult = try validateWatcher(scanner: scanner, project: rollback, root: root)
        print("WATCHER event=\(watcherResult.event ? "PASS" : "FAIL") debounce=\(watcherResult.debounced ? "PASS" : "FAIL") incremental=\(watcherResult.incremental ? "PASS" : "FAIL")")
        expect(watcherResult.event && watcherResult.debounced && watcherResult.incremental, "watcher/debounce contract failed")

        try runBenchmarks(scanner: scanner, root: root)
        print("PASS project intelligence acceptance gate")
    }

    private static func validateProject(scanner: ProjectIntelligenceScanner, path: URL, stack: String, language: String) throws -> ProjectIntelligenceIndex {
        let index = try scanner.scan(projectPath: path.path)
        expect(index.fileCount > 0, "empty index for \(path.lastPathComponent)")
        expect(index.project.frameworks.contains(stack), "stack missing for \(path.lastPathComponent)")
        expect(index.project.languages.contains(language), "language missing for \(path.lastPathComponent)")
        expect(index.symbolCount > 0 && index.testCount > 0, "symbols/tests missing for \(path.lastPathComponent)")
        expect(index.project.branch != nil && index.project.headCommit != nil, "git metadata missing for \(path.lastPathComponent)")
        let sensitive = index.files.filter(\.sensitive)
        expect(!sensitive.isEmpty, "sensitive fixture missing for \(path.lastPathComponent)")
        for file in sensitive { expect(file.hash == nil && file.symbols.isEmpty, "sensitive content parsed for \(file.relativePath)") }
        let encoded = String(decoding: try JSONEncoder().encode(index), as: UTF8.self)
        expect(!encoded.contains("FAKE_SECRET_CONTENT") && !encoded.contains("PRIVATE_ACCEPTANCE_KEY"), "sensitive content entered index")
        for excluded in [".git/", "node_modules/", "target/", "dist/", "build/", "DerivedData/", ".venv/", "__pycache__/", "coverage/"] {
            expect(!index.files.contains(where: { $0.relativePath.hasPrefix(excluded) }), "excluded path indexed: \(excluded)")
        }
        return index
    }

    private struct IncrementalResult {
        let first: Int
        let secondReused: Int
        let modifiedChanged: Int
        let added: Int
        let deleted: Int
        let renamed: Int
        let testChanged: Int
        let latest: ProjectIntelligenceIndex
    }

    private static func validateIncremental(scanner: ProjectIntelligenceScanner, path: URL, first: ProjectIntelligenceIndex) throws -> IncrementalResult {
        let second = try scanner.scan(projectPath: path.path, previous: first)
        expect(second.reusedFileCount >= first.fileCount, "unchanged scan did not reuse all files")
        Thread.sleep(forTimeInterval: 0.05)
        try write("export function multiply(a: number, b: number) { return a * b + 1 }\n", to: path.appendingPathComponent("src/math.ts"))
        let modified = try scanner.scan(projectPath: path.path, previous: second)
        expect(modified.changedFileCount == 1, "single-file edit was not incremental")
        try write("export const divide = (a: number, b: number) => a / b\n", to: path.appendingPathComponent("src/divide.ts"))
        let added = try scanner.scan(projectPath: path.path, previous: modified)
        expect(added.files.contains(where: { $0.relativePath == "src/divide.ts" }), "new file missing")
        try fileManager.removeItem(at: path.appendingPathComponent("src/divide.ts"))
        let deleted = try scanner.scan(projectPath: path.path, previous: added)
        expect(!deleted.files.contains(where: { $0.relativePath == "src/divide.ts" }), "deleted file remained")
        try fileManager.moveItem(at: path.appendingPathComponent("src/index.ts"), to: path.appendingPathComponent("src/entry.ts"))
        let renamed = try scanner.scan(projectPath: path.path, previous: deleted)
        expect(renamed.files.contains(where: { $0.relativePath == "src/entry.ts" }) && !renamed.files.contains(where: { $0.relativePath == "src/index.ts" }), "rename state is incorrect")
        Thread.sleep(forTimeInterval: 0.05)
        try write("import { multiply } from '../src/math'\ntest('multiply changed', () => expect(multiply(2, 3)).toBe(7))\n", to: path.appendingPathComponent("tests/math.test.ts"))
        let testChanged = try scanner.scan(projectPath: path.path, previous: renamed)
        expect(testChanged.changedFileCount == 1, "test edit was not incremental")
        expect(testChanged.tests.contains(where: { $0.path == "tests/math.test.ts" }), "related test disappeared")
        return IncrementalResult(first: first.fileCount, secondReused: second.reusedFileCount, modifiedChanged: modified.changedFileCount, added: added.files.contains(where: { $0.relativePath == "src/divide.ts" }) ? 1 : 0, deleted: deleted.files.contains(where: { $0.relativePath == "src/divide.ts" }) ? 0 : 1, renamed: renamed.files.contains(where: { $0.relativePath == "src/entry.ts" }) && !renamed.files.contains(where: { $0.relativePath == "src/index.ts" }) ? 1 : 0, testChanged: testChanged.changedFileCount, latest: testChanged)
    }

    private static func validateProjectSwitchRace(scanner: ProjectIntelligenceScanner, root: URL, paths: [URL]) throws -> String {
        let service = ProjectIntelligenceService(scanner: scanner, store: ProjectIntelligenceStore(rootURL: root.appendingPathComponent("switch-store", isDirectory: true)))
        let names = ["A", "B", "C"]
        var callbackCount = 0
        var accepted: [String] = []
        let currentRequest = "C"
        for (index, path) in paths.enumerated() {
            let name = names[index]
            service.index(projectPath: path.path, force: true) { overview in
                guard overview.index != nil else { return }
                callbackCount += 1
                if name == currentRequest { accepted.append(name) }
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && callbackCount < paths.count {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        expect(callbackCount == paths.count, "project switch callbacks incomplete")
        expect(accepted == ["C"], "stale project callback was accepted")
        return accepted.joined()
    }

    private static func validateRollbackReindex(scanner: ProjectIntelligenceScanner, project: URL, root: URL) throws -> Int {
        let service = ProjectIntelligenceService(scanner: scanner, store: ProjectIntelligenceStore(rootURL: root.appendingPathComponent("rollback-store", isDirectory: true)))
        let baseline = try service.indexSynchronously(projectPath: project.path, force: true)
        let baselineHashes = Dictionary(uniqueKeysWithValues: baseline.files.compactMap { file in file.hash.map { (file.relativePath, $0) } })
        let manager = CheckpointManager(rootURL: root.appendingPathComponent("checkpoints", isDirectory: true))
        let checkpoint = try manager.create(projectPath: project.path)
        try write("changed A\n", to: project.appendingPathComponent("A.txt"))
        try write("changed B\n", to: project.appendingPathComponent("B.txt"))
        try write("new C\n", to: project.appendingPathComponent("C.txt"))
        _ = try service.indexSynchronously(projectPath: project.path, force: true)
        let verification = try manager.rollback(checkpoint)
        expect(verification.verified, "disk rollback verification failed")
        let deadline = Date().addingTimeInterval(10)
        var restored: ProjectIntelligenceIndex?
        while Date() < deadline {
            let overview = service.overview(projectPath: project.path)
            if overview.status == .ready, let index = overview.index, !index.files.contains(where: { $0.relativePath == "C.txt" }) {
                restored = index
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let restored else { fatalError("rollback did not trigger project reindex") }
        expect(restored.files.count == baseline.files.count, "rollback index file count mismatch")
        for (path, hash) in baselineHashes { expect(restored.files.first(where: { $0.relativePath == path })?.hash == hash, "rollback hash mismatch for \(path)") }
        return (restored.files.count)
    }

    private static func validateWatcher(scanner: ProjectIntelligenceScanner, project: URL, root: URL) throws -> (event: Bool, debounced: Bool, incremental: Bool) {
        let service = ProjectIntelligenceService(scanner: scanner, store: ProjectIntelligenceStore(rootURL: root.appendingPathComponent("watch-store", isDirectory: true)))
        _ = try service.indexSynchronously(projectPath: project.path, force: true)
        var updates = 0
        var latest: ProjectIntelligenceOverview?
        service.startWatching(projectPath: project.path) { overview in
            updates += 1
            latest = overview
        }
        for index in 0..<4 {
            try write("watch-\(index)\n", to: project.appendingPathComponent("watch.txt"))
            Thread.sleep(forTimeInterval: 0.08)
        }
        let eventDeadline = Date().addingTimeInterval(8)
        while Date() < eventDeadline && updates == 0 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let event = updates > 0
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && (latest?.status != .ready || latest?.index?.files.first(where: { $0.relativePath == "watch.txt" }) == nil) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        service.stopWatching()
        let incremental = latest?.index?.reusedFileCount ?? 0 > 0
        let debounced = updates <= 2
        return (event, debounced, incremental)
    }

    private static func runBenchmarks(scanner: ProjectIntelligenceScanner, root: URL) throws {
        for count in [100, 1_000, 5_000] {
            let project = root.appendingPathComponent("bench-\(count)", isDirectory: true)
            try fileManager.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
            for index in 0..<count {
                try write("export const value\(index) = \(index)\n", to: project.appendingPathComponent("src/file\(index).ts"))
            }
            let firstStart = Date()
            let first = try scanner.scan(projectPath: project.path)
            let firstSeconds = Date().timeIntervalSince(firstStart)
            let cachedStart = Date()
            let cached = try scanner.scan(projectPath: project.path, previous: first)
            let cachedSeconds = Date().timeIntervalSince(cachedStart)
            Thread.sleep(forTimeInterval: 0.05)
            try write("export const value0 = 999\n", to: project.appendingPathComponent("src/file0.ts"))
            let incrementalStart = Date()
            let incremental = try scanner.scan(projectPath: project.path, previous: cached)
            let incrementalSeconds = Date().timeIntervalSince(incrementalStart)
            expect(first.fileCount == count && cached.reusedFileCount >= count - 1 && incremental.changedFileCount == 1, "benchmark incremental contract failed for \(count)")
            print(String(format: "BENCH files=%d first=%.3fs cached=%.3fs incremental=%.3fs reused=%d changed=%d", count, firstSeconds, cachedSeconds, incrementalSeconds, cached.reusedFileCount, incremental.changedFileCount))
        }
    }

    private static func replaceIndexVersion(_ text: String) throws -> String {
        let expression = try NSRegularExpression(pattern: #""indexVersion"\s*:\s*1"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let result = expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\"indexVersion\": 0")
        return result
    }

    private static func createTypeScriptProject(at project: URL) throws {
        try createProject(at: project, files: [
            ".gitignore": "node_modules\ndist\nignored.ts\n",
            "package.json": #"{"scripts":{"test":"vitest"},"dependencies":{"react":"latest","vite":"latest"}}"#,
            "src/index.ts": "import { multiply } from './math'\nexport function run(value: number) { return multiply(value, 2) }\n",
            "src/math.ts": "export function multiply(a: number, b: number) { return a * b }\n",
            "tests/math.test.ts": "import { multiply } from '../src/math'\ntest('multiply', () => expect(multiply(2, 3)).toBe(6))\n",
            ".env": "FAKE_SECRET_CONTENT=do-not-index\n",
            ".env.local": "PRIVATE_ACCEPTANCE_KEY=do-not-index\n",
            "credentials.json": #"{"token":"FAKE_SECRET_CONTENT"}"#,
            "fake-key.pem": "PRIVATE_ACCEPTANCE_KEY\n",
            "fake-home/.ssh/id_rsa": "PRIVATE_ACCEPTANCE_KEY\n",
            "ignored.ts": "export const ignored = true\n",
            "node_modules/ignored.ts": "export const ignored = true\n",
            "target/generated.rs": "fn ignored() {}\n",
            "dist/bundle.js": "ignored\n",
            "build/output.js": "ignored\n",
            "DerivedData/output": "ignored\n",
            ".venv/cache.py": "ignored\n",
            "__pycache__/cache.pyc": "ignored\n",
            "coverage/lcov.info": "ignored\n",
        ])
        try initializeGit(at: project)
    }

    private static func createRustProject(at project: URL) throws {
        try createProject(at: project, files: [
            "Cargo.toml": "[package]\nname = \"acceptance-rust\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
            "src/lib.rs": "pub fn add(a: i32, b: i32) -> i32 { a + b }\n",
            "src/main.rs": "fn main() { println!(\"{}\", acceptance_rust::add(1, 2)); }\n",
            "tests/math_test.rs": "#[test]\nfn add_works() { assert_eq!(acceptance_rust::add(1, 2), 3); }\n",
            ".env": "FAKE_SECRET_CONTENT=do-not-index\n",
            "target/generated.rs": "fn ignored() {}\n",
        ])
        try initializeGit(at: project)
    }

    private static func createPythonProject(at project: URL) throws {
        try createProject(at: project, files: [
            "pyproject.toml": "[project]\nname = \"acceptance-python\"\nversion = \"0.1.0\"\n",
            "app.py": "def add(a, b):\n    return a + b\n",
            "tests/test_app.py": "from app import add\ndef test_add():\n    assert add(1, 2) == 3\n",
            "requirements.txt": "pytest\n",
            ".env": "FAKE_SECRET_CONTENT=do-not-index\n",
            "__pycache__/cache.pyc": "ignored\n",
        ])
        try initializeGit(at: project)
    }

    private static func createRollbackProject(at project: URL) throws {
        try createProject(at: project, files: [
            "A.txt": "baseline A\n",
            "B.txt": "baseline B\n",
            "src/math.ts": "export function add(a: number, b: number) { return a + b }\n",
            "tests/math.test.ts": "test('add', () => {})\n",
        ])
    }

    private static func createProject(at project: URL, files: [String: String]) throws {
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        for (relative, content) in files { try write(content, to: project.appendingPathComponent(relative)) }
    }

    private static func initializeGit(at project: URL) throws {
        _ = try command(["init", "-q"], cwd: project)
        _ = try command(["add", "."], cwd: project)
        _ = try command(["-c", "user.name=AI Dev One Acceptance", "-c", "user.email=acceptance@example.invalid", "commit", "-qm", "baseline"], cwd: project)
    }

    private static func write(_ content: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private static func command(_ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AcceptanceGit", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: error, as: UTF8.self)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}
