import Foundation

/// Explicitly gated utility used only by the Phase 3.7 installed-App
/// acceptance. It creates/removes one marked transaction and never touches
/// credentials, remote resources, or unrelated task records.
@main
struct GitHubCILiveAcceptance {
    static func main() {
        guard ProcessInfo.processInfo.environment["AI_DEV_ONE_LIVE_ACCEPTANCE"] == "1" else {
            fatalError("AI_DEV_ONE_LIVE_ACCEPTANCE=1 is required")
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { fatalError("usage: seed|status|remove") }
        let store = TaskTransactionStore.shared

        switch command {
        case "seed":
            guard arguments.count >= 4 else { fatalError("seed <run-id> <attempt> <remote-sha>") }
            let runID = arguments[1]
            let attempt = Int(arguments[2])
            let remoteSHA = arguments[3]
            let repository = GitHubRepositoryBinding(
                owner: "liuds66",
                repo: "grok-build",
                remoteName: "origin",
                remoteURL: "https://github.com/liuds66/grok-build.git",
                defaultBranch: "v0.5-dev",
                repositoryID: nil
            )
            var transaction = TaskTransaction(
                sessionId: "phase-3-7-live-acceptance",
                projectPath: "/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座",
                checkpointId: "phase-3-7-read-only"
            )
            _ = transaction.transition(to: .planning)
            _ = transaction.transition(to: .building)
            _ = transaction.transition(to: .testing)
            _ = transaction.transition(to: .reviewing)
            transaction.pipeline = AgentPipelineSnapshot(states: [
                .architect: .passed,
                .builder: .passed,
                .verifier: .passed,
                .reviewer: .passed,
            ])
            var metadata = GitHubTaskMetadata(
                repository: repository,
                issueNumber: 1,
                issueTitle: "Phase 3.7 lifecycle acceptance",
                taskBranch: "ai-dev-one/issue-1-github-remote-roles",
                baseBranch: "v0.5-dev",
                autonomousMode: true
            )
            metadata.localCommitSHA = remoteSHA
            metadata.remoteCommitSHA = remoteSHA
            metadata.pullRequestNumber = 2
            metadata.pullRequestURL = "https://github.com/liuds66/grok-build/pull/2"
            metadata.pullRequestRef = metadata.taskBranch
            metadata.ciRunId = runID
            metadata.ciRunAttempt = attempt
            metadata.ciLastObservedState = .queued
            metadata.record(.waitingCI)
            transaction.github = metadata
            store.upsert(transaction, forcePersist: true)
            print("taskId=\(transaction.taskId)")
            print("state=waiting_ci")
            print("pr=2")

        case "status":
            guard arguments.count == 2,
                  let transaction = store.transaction(id: arguments[1]),
                  let metadata = transaction.github else { fatalError("transaction not found") }
            print("taskId=\(transaction.taskId)")
            print("finalState=\(transaction.finalState.rawValue)")
            print("githubWorkflowState=\(metadata.workflowState.rawValue)")
            print("pr=\(metadata.pullRequestNumber.map(String.init) ?? "nil")")
            print("run=\(metadata.ciRunId ?? "nil")")
            print("attempt=\(metadata.ciRunAttempt.map(String.init) ?? "nil")")
            print("ci=\(metadata.ciLastObservedState?.rawValue ?? "nil")")
            print("cancellationSource=\(transaction.cancellationSource?.rawValue ?? "nil")")

        case "remove":
            guard arguments.count == 2 else { fatalError("remove <task-id>") }
            store.remove(taskID: arguments[1])
            print("removed=\(arguments[1])")

        default:
            fatalError("usage: seed|status|remove")
        }
    }
}
