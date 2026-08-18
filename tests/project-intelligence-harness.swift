import Foundation

@main
struct ProjectIntelligenceHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.appendingPathComponent("tests"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.appendingPathComponent("node_modules/ignored"), withIntermediateDirectories: true)
        try "node_modules\nignored.ts\n".write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "{\"scripts\":{\"test\":\"vitest\"},\"dependencies\":{\"react\":\"latest\",\"vite\":\"latest\"}}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "import { multiply } from './math'\nexport function run(value: number) { return multiply(value, 2) }\n".write(to: project.appendingPathComponent("src/index.ts"), atomically: true, encoding: .utf8)
        try "export function multiply(a: number, b: number) { return a * b }\n".write(to: project.appendingPathComponent("src/math.ts"), atomically: true, encoding: .utf8)
        try "import { multiply } from '../src/math'\ntest('multiply', () => expect(multiply(2, 3)).toBe(6))\n".write(to: project.appendingPathComponent("tests/math.test.ts"), atomically: true, encoding: .utf8)
        try "PRIVATE_TEST_SECRET=do-not-index\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "export const ignored = true".write(to: project.appendingPathComponent("node_modules/ignored/bad.ts"), atomically: true, encoding: .utf8)
        _ = try? runGit(["init"], in: project)

        let scanner = ProjectIntelligenceScanner()
        let first = try scanner.scan(projectPath: project.path)
        guard first.indexVersion == projectIntelligenceIndexVersion else { fatalError("index version") }
        guard first.files.contains(where: { $0.relativePath == "src/math.ts" }) else { fatalError("source file missing") }
        guard !first.files.contains(where: { $0.relativePath.contains("node_modules") }) else { fatalError("ignored dependency indexed") }
        guard first.files.first(where: { $0.relativePath == ".env" })?.sensitive == true else { fatalError("sensitive file not marked") }
        guard first.files.first(where: { $0.relativePath == ".env" })?.hash == nil else { fatalError("sensitive hash/content leaked") }
        guard first.symbols.contains(where: { $0.name == "multiply" && $0.kind == "function" }) else { fatalError("symbol missing") }
        guard first.project.frameworks.contains("React") && first.project.frameworks.contains("Vite") else { fatalError("stack detection") }
        guard first.tests.contains(where: { $0.path == "tests/math.test.ts" }) else { fatalError("test intelligence missing") }
        guard first.dependencies.contains(where: { $0.from == "src/index.ts" && $0.to == "src/math.ts" }) else { fatalError("dependency relation missing") }

        let second = try scanner.scan(projectPath: project.path, previous: first)
        guard second.reusedFileCount >= first.files.count - 1 else { fatalError("incremental reuse too low") }
        try "export function multiply(a: number, b: number) { return a * b + 1 }\n".write(to: project.appendingPathComponent("src/math.ts"), atomically: true, encoding: .utf8)
        let third = try scanner.scan(projectPath: project.path, previous: second)
        guard third.changedFileCount >= 1 else { fatalError("changed file not reindexed") }

        let store = ProjectIntelligenceStore(rootURL: root.appendingPathComponent("index-store"))
        let service = ProjectIntelligenceService(scanner: scanner, store: store)
        _ = try service.indexSynchronously(projectPath: project.path, force: true)
        let provider = ProjectContextProvider(service: service)
        let relevant = provider.findRelevantFiles(projectPath: project.path, query: "multiply button", limit: 4)
        guard relevant.first?.relativePath == "src/math.ts" else { fatalError("deterministic relevance ranking") }
        let context = provider.promptContext(projectPath: project.path, query: "multiply")
        guard context.contains("src/math.ts") && context.count < 6_500 else { fatalError("bounded context") }
        let knowledge = TaskKnowledge(taskId: "task-1", summary: "add multiply sk-live-secret-value", filesRead: ["src/math.ts bearer live-secret-value"], filesChanged: ["src/math.ts"], symbolsChanged: ["multiply"], verification: ["Node test: PASS"], finalState: "completed", recordedAt: Date())
        let done = DispatchSemaphore(value: 0)
        service.recordTaskKnowledge(knowledge, projectPath: project.path) { done.signal() }
        _ = done.wait(timeout: .now() + 5)
        let knowledgeAfter = try service.indexSynchronously(projectPath: project.path).taskKnowledge
        guard let persistedKnowledge = knowledgeAfter.first(where: { $0.taskId == "task-1" }) else { fatalError("task knowledge not persisted") }
        let serializedKnowledge = String(describing: persistedKnowledge)
        guard !serializedKnowledge.contains("sk-live-secret-value") && !serializedKnowledge.contains("live-secret-value") else { fatalError("task knowledge secret leaked") }
        print("project-intelligence files=\(first.fileCount) symbols=\(first.symbolCount) tests=\(first.testCount) reused=\(second.reusedFileCount) changed=\(third.changedFileCount) context=PASS")
    }

    private static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
