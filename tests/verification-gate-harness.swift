import Foundation

@main
struct VerificationGateHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let unknown = root.appendingPathComponent("unknown", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        let unknownPlan = VerificationGate.plannedChecks(projectPath: unknown.path)
        guard unknownPlan.count == 1, unknownPlan[0].2?.contains("未识别") == true else { fatalError("unknown project must be skipped") }
        let node = root.appendingPathComponent("node", isDirectory: true)
        try FileManager.default.createDirectory(at: node, withIntermediateDirectories: true)
        try "{\"scripts\":{\"test\":\"true\"}}".write(to: node.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let nodePlan = VerificationGate.plannedChecks(projectPath: node.path)
        guard nodePlan.count == 4, nodePlan.contains(where: { $0.0 == "Node test" && $0.1 == "npm run test" }) else { fatalError("Node verification plan missing") }
        print("unknown=SKIPPED node-plan=PASS")
    }
}
