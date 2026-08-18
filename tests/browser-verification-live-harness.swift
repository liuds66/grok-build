import AppKit
import Foundation
import Darwin

@main
struct BrowserVerificationLiveHarness {
    private static var portCounter = 0

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-dev-one-browser-fixture-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let port = 43217 + Int(getpid() % 100)
        writeFixture(root: root, port: port)

        let normal = verify(root: root, taskID: "fixture-normal", viewport: .desktop)
        let normalTiming = normal?.timingsMS.map { "\($0.key)=\(String(format: "%.1f", $0.value))" }.sorted().joined(separator: ",") ?? ""
        print("fixture.normal=\(normal?.status.rawValue ?? "missing") screenshots=\(normal?.screenshots.count ?? 0) console=\(normal?.consoleMessages.count ?? -1) network=\(normal?.failedRequests.count ?? -1) layout=\(normal?.layoutFindings.count ?? -1) timings=\(normalTiming)")
        guard normal?.status == .passed, normal?.screenshots.isEmpty == false else { fail("normal fixture") }

        let console = verify(root: root, taskID: "fixture-console", viewport: .desktop, path: "/console")
        print("fixture.console=\(console?.status.rawValue ?? "missing") errors=\(console?.consoleMessages.count ?? -1) instrumented=\(console?.instrumentationInstalled ?? false) summary=\(console?.summary ?? "missing")")
        guard console?.status == .failed, (console?.consoleMessages.isEmpty == false || console?.pageErrors.isEmpty == false) else { fail("console fixture") }

        let network = verify(root: root, taskID: "fixture-network", viewport: .desktop, path: "/network")
        print("fixture.network=\(network?.status.rawValue ?? "missing") failed=\(network?.failedRequests.count ?? -1)")
        guard network?.status == .failed, network?.failedRequests.isEmpty == false else { fail("network fixture") }

        let overflow = verify(root: root, taskID: "fixture-overflow", viewport: .desktop, path: "/overflow")
        print("fixture.overflow=\(overflow?.status.rawValue ?? "missing") findings=\(overflow?.layoutFindings.count ?? -1) summary=\(overflow?.summary ?? "missing") url=\(overflow?.devServerURL ?? "missing")")
        guard overflow?.status == .failed, overflow?.layoutFindings.contains(where: { $0.code == "horizontal_overflow" }) == true else { fail("overflow fixture") }

        let responsive = verify(root: root, taskID: "fixture-responsive", viewport: .mobile, path: "/responsive")
        print("fixture.responsive=\(responsive?.status.rawValue ?? "missing") viewport=\(responsive?.viewport.width ?? -1)x\(responsive?.viewport.height ?? -1)")
        guard responsive?.status == .failed else { fail("responsive fixture") }

        let firstRepair = verify(root: root, taskID: "fixture-self-repair", viewport: .desktop, path: "/self-repair")
        print("self_repair.first_pre=\(firstRepair?.status.rawValue ?? "missing") layout=\(firstRepair?.layoutFindings.count ?? -1) url=\(firstRepair?.devServerURL ?? "missing") summary=\(firstRepair?.summary ?? "missing")")
        guard firstRepair?.status == .failed else { fail("self-repair first failure") }
        try! Data("fixed\n".utf8).write(to: root.appendingPathComponent("repair.flag"), options: .atomic)
        let repaired = verify(root: root, taskID: "fixture-self-repair", viewport: .desktop, path: "/self-repair")
        print("self_repair.first=\(firstRepair?.status.rawValue ?? "missing") second=\(repaired?.status.rawValue ?? "missing") summary=\(repaired?.summary ?? "missing")")
        guard repaired?.status == .passed else { fail("self-repair second pass") }

        BrowserEvidenceStore.cleanup(taskID: "fixture-normal")
        BrowserEvidenceStore.cleanup(taskID: "fixture-console")
        BrowserEvidenceStore.cleanup(taskID: "fixture-network")
        BrowserEvidenceStore.cleanup(taskID: "fixture-overflow")
        BrowserEvidenceStore.cleanup(taskID: "fixture-responsive")
        BrowserEvidenceStore.cleanup(taskID: "fixture-self-repair")
        print("process.cleanup=\(BrowserVerificationService.shared.activeSession == nil)")
        print("PASS browser verification live fixtures")
    }

    private static func verify(root: URL, taskID: String, viewport: BrowserViewport, path: String = "/", retryOnError: Bool = true) -> BrowserVerificationResult? {
        var result: BrowserVerificationResult?
        if portCounter > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        }
        portCounter += 1
        let port = 44000 + Int(getpid() % 500) + portCounter
        updateFixturePort(root: root, port: port)
        let base = DevServerPlan.detect(projectPath: root.path)?.configuredURL ?? "http://localhost:43217/"
        let requestedURL: String
        if path == "/" {
            requestedURL = base
        } else if base.hasSuffix("/") {
            requestedURL = String(base.dropLast()) + path
        } else {
            requestedURL = base + path
        }
        BrowserVerificationService.shared.verify(projectPath: root.path, taskID: taskID, requestedURL: requestedURL, viewport: viewport) {
            result = $0
        }
        let deadline = Date().addingTimeInterval(60)
        while result == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if retryOnError, result?.status == .error {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            return verify(root: root, taskID: taskID, viewport: viewport, path: path, retryOnError: false)
        }
        return result
    }

    private static func writeFixture(root: URL, port: Int) {
        let packageObject: [String: Any] = [
            "scripts": ["dev": "node server.js"],
            "dependencies": ["vite": "0.0.0", "react": "0.0.0"],
            "aiDevOne": ["browserVerification": ["url": "http://localhost:\(port)/"]],
        ]
        let packageData = try! JSONSerialization.data(withJSONObject: packageObject, options: [.sortedKeys])
        try! packageData.write(to: root.appendingPathComponent("package.json"), options: .atomic)
        try! "\(port)\n".write(to: root.appendingPathComponent("port.txt"), atomically: true, encoding: .utf8)
        let server = """
        const http = require('http');
        const fs = require('fs');
        process.title = 'ai-dev-one-browser-fixture';
        const port = Number(fs.readFileSync('port.txt', 'utf8')) || \(port);
        const page = (mode) => {
          const base = '<!doctype html><html><head><meta charset="utf-8"><title>AI Dev One Fixture</title><style>body{font-family:system-ui;margin:24px}button{padding:10px 18px}</style></head><body><main><h1>Fixture</h1><button id="save">Save</button>';
          if (mode === 'console') return base + '<script>setTimeout(() => console.error("fixture console error"), 50)</script></main></body></html>';
          if (mode === 'network') return base + '<script>fetch("/missing.js").catch(()=>{})</script></main></body></html>';
          if (mode === 'overflow') return base + '<div style="width:3000px;height:20px;background:#123"></div></main></body></html>';
          if (mode === 'responsive') return base + '<style>@media(max-width:500px){body{width:1200px}}</style></main></body></html>';
          if (mode === 'self-repair' && !fs.existsSync('repair.flag')) return base + '<div style="width:3000px;height:20px"></div></main></body></html>';
          return base + '<p>healthy local page</p></main></body></html>';
        };
        const server = http.createServer((req,res) => {
          const mode = (req.url || '/').split('?')[0].slice(1) || 'normal';
          if (req.url === '/missing.js') { res.writeHead(404); res.end('missing'); return; }
          const body = page(mode);
          res.writeHead(200, {'content-type':'text/html; charset=utf-8'});
          res.end(body);
        });
        server.listen(port, '127.0.0.1', () => console.log('http://localhost:' + port + '/'));
        process.on('SIGTERM', () => server.close(() => process.exit(0)));
        """
        try! server.write(to: root.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)
    }

    private static func updateFixturePort(root: URL, port: Int) {
        let packageObject: [String: Any] = [
            "scripts": ["dev": "node server.js"],
            "dependencies": ["vite": "0.0.0", "react": "0.0.0"],
            "aiDevOne": ["browserVerification": ["url": "http://localhost:\(port)/"]],
        ]
        let packageData = try! JSONSerialization.data(withJSONObject: packageObject, options: [.sortedKeys])
        try! packageData.write(to: root.appendingPathComponent("package.json"), options: .atomic)
        try! "\(port)\n".write(to: root.appendingPathComponent("port.txt"), atomically: true, encoding: .utf8)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("FAIL \(message)\n").utf8))
        exit(1)
    }
}
