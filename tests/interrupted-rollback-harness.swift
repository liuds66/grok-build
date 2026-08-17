import Foundation

@main
struct InterruptedRollbackHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try "before".write(to: project.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        let manager = CheckpointManager(rootURL: root.appendingPathComponent("checkpoints"))
        let checkpoint = try manager.create(projectPath: project.path)
        var transaction = TaskTransaction(sessionId: "session-test", projectPath: project.path, checkpointId: checkpoint.id)
        transaction.transition(to: .building)
        try "partial builder write".write(to: project.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "partial new file".write(to: project.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        transaction.transition(to: .interrupted)
        let rollback = try manager.rollback(checkpoint)
        guard rollback.verified,
              transaction.finalState == .interrupted,
              try String(contentsOf: project.appendingPathComponent("tracked.txt")) == "before",
              !fm.fileExists(atPath: project.appendingPathComponent("new.txt").path) else {
            throw NSError(domain: "InterruptedRollback", code: 1, userInfo: [NSLocalizedDescriptionKey: "interrupted 任务未恢复磁盘内容"])
        }
        transaction.transition(to: .rolledBack)
        print("interrupted=true rollback=true finalState=\(transaction.finalState.rawValue)")
    }
}
