import Foundation
import CryptoKit

@main
struct CheckpointRollbackExtendedHarness {
    static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let storage = root.appendingPathComponent("checkpoints", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try "alpha".write(to: project.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "bravo".write(to: project.appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
        try "charlie".write(to: project.appendingPathComponent("dir/C.txt"), atomically: true, encoding: .utf8)

        let expected: [String: String] = [
            "A.txt": try digest(project.appendingPathComponent("A.txt")),
            "B.txt": try digest(project.appendingPathComponent("B.txt")),
            "dir/C.txt": try digest(project.appendingPathComponent("dir/C.txt")),
        ]
        let manager = CheckpointManager(rootURL: storage)
        let checkpoint = try manager.create(projectPath: project.path)

        try "changed".write(to: project.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try fm.removeItem(at: project.appendingPathComponent("B.txt"))
        try "new file".write(to: project.appendingPathComponent("D.txt"), atomically: true, encoding: .utf8)
        try fm.moveItem(at: project.appendingPathComponent("dir/C.txt"), to: project.appendingPathComponent("dir/C2.txt"))
        try fm.createDirectory(at: project.appendingPathComponent("new-directory/nested"), withIntermediateDirectories: true)
        try "extra".write(to: project.appendingPathComponent("new-directory/nested/extra.txt"), atomically: true, encoding: .utf8)

        let result = try manager.rollback(checkpoint)
        let restoredA = try digest(project.appendingPathComponent("A.txt"))
        let restoredB = try digest(project.appendingPathComponent("B.txt"))
        let restoredC = try digest(project.appendingPathComponent("dir/C.txt"))
        guard result.verified,
              !fm.fileExists(atPath: project.appendingPathComponent("D.txt").path),
              !fm.fileExists(atPath: project.appendingPathComponent("dir/C2.txt").path),
              !fm.fileExists(atPath: project.appendingPathComponent("new-directory").path),
              expected["A.txt"] == restoredA,
              expected["B.txt"] == restoredB,
              expected["dir/C.txt"] == restoredC else {
            throw NSError(domain: "CheckpointExtended", code: 1, userInfo: [NSLocalizedDescriptionKey: "SHA-256 或文件树未恢复"])
        }
        print("verified=true sha256=true restored=\(result.restoredFiles) removed=\(result.removedFiles)")
    }
}
