import Foundation

@main
struct CheckpointRollbackHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let storage = root.appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "one".write(to: project.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: project.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "three".write(to: project.appendingPathComponent("src/c.txt"), atomically: true, encoding: .utf8)
        let manager = CheckpointManager(rootURL: storage)
        let checkpoint = try manager.create(projectPath: project.path)

        try "changed".write(to: project.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "changed".write(to: project.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "changed".write(to: project.appendingPathComponent("src/c.txt"), atomically: true, encoding: .utf8)
        try "added one".write(to: project.appendingPathComponent("new-1.txt"), atomically: true, encoding: .utf8)
        try "added two".write(to: project.appendingPathComponent("new-2.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: project.appendingPathComponent("b.txt"))

        let result = try manager.rollback(checkpoint)
        guard result.verified,
      try String(contentsOf: project.appendingPathComponent("a.txt")) == "one",
      try String(contentsOf: project.appendingPathComponent("b.txt")) == "two",
      try String(contentsOf: project.appendingPathComponent("src/c.txt")) == "three",
      !FileManager.default.fileExists(atPath: project.appendingPathComponent("new-1.txt").path),
      !FileManager.default.fileExists(atPath: project.appendingPathComponent("new-2.txt").path) else {
            throw NSError(domain: "CheckpointTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "磁盘内容未恢复"])
        }
        print("verified=true restored=\(result.restoredFiles) removed=\(result.removedFiles)")
    }
}
