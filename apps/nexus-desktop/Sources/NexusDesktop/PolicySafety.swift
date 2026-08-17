import Foundation

enum PolicyDecision: String, Codable {
    case allow
    case ask
    case deny
}

/// Explicit fail-closed rules passed to the existing Rust permission engine.
/// The desktop layer never executes a command itself; these rules are an
/// additional boundary before the Rust tool runtime sees a Bash/Edit request.
enum NexusPolicyRules {
    static let denyRules: [String] = [
        "Bash(rm -rf*)",
        "Bash(sudo*)",
        "Bash(git push --force*)",
        "Bash(git push -f*)",
        "Bash(git reset --hard*)",
        "Bash(git clean -fd*)",
        "Bash(git clean -f*)",
        "Bash(chmod -R*)",
        "Bash(*~/.ssh*)",
        "Bash(*.env*)",
        "Read(**/.env*)",
        "Read(**/.ssh/**)",
        "Read(**/id_rsa*)",
        "Edit(**/.env*)",
        "Edit(**/.ssh/**)",
    ]

    static var commandLineArguments: [String] {
        denyRules.flatMap { ["--deny", $0] }
    }
}

/// A conservative UI preflight used for audit messages and tests. The actual
/// allow/ask/deny boundary remains the Rust permission engine above; this
/// helper intentionally never grants a command that the engine did not see.
enum PolicyPreflight {
    static func evaluate(command: String, projectPath: String) -> PolicyDecision {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return .deny }
        if normalized.contains("rm -rf")
            || normalized.contains("sudo")
            || normalized.contains("git reset --hard")
            || normalized.contains("git clean -f")
            || normalized.contains("chmod -r")
            || normalized.contains("~/.ssh")
            || normalized.contains(".env") {
            return .deny
        }
        if normalized.contains("git push") || normalized.contains("delete") || normalized.contains("outside") {
            return .ask
        }
        return projectPath.isEmpty ? .ask : .allow
    }
}
