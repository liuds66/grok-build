import Foundation
import Darwin

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL \(message)\n").utf8))
    exit(1)
}

@main
struct BrowserVerificationHarness {
    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-dev-one-browser-contract-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let package = #"{"scripts":{"dev":"node server.js"},"dependencies":{"vite":"latest","react":"latest"},"aiDevOne":{"browserVerification":{"url":"http://localhost:43127/"}}}"#
        try! package.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let plan = DevServerPlan.detect(projectPath: root.path)
        guard plan?.displayCommand == "npm run dev", plan?.framework == "Vite", plan?.configuredURL == "http://localhost:43127/" else {
            fail("DevServerPlan detection")
        }
        guard BrowserURLPolicy.isAllowed("http://localhost:43127/"), BrowserURLPolicy.isAllowed("https://127.0.0.1:8443/path") else {
            fail("localhost allowlist")
        }
        guard !BrowserURLPolicy.isAllowed("https://example.com/"), !BrowserURLPolicy.isAllowed("file:///tmp/secret") else {
            fail("external/file URL must be blocked")
        }
        guard BrowserURLPolicy.sanitizedString("http://localhost:43127/?token=secret#fragment") == "http://localhost:43127/" else {
            fail("URL query redaction")
        }
        let redacted = BrowserVerificationRedaction.text("Authorization: Bearer sk-test-secret-1234567890 API_KEY=sk-test-secret-1234567890")
        guard !redacted.contains("sk-test-secret-1234567890"), redacted.contains("<redacted>") else {
            fail("credential redaction")
        }
        try? FileManager.default.removeItem(at: root)
        print("PASS browser verification plan/URL contract")
    }
}
