import Foundation

@main
struct TransactionHarness {
    static func main() {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = TaskTransactionStore(fileURL: file)
        var transaction = TaskTransaction(sessionId: "session", projectPath: "/tmp/project", checkpointId: "checkpoint")
        transaction.transition(to: .planning)
        transaction.appendCommand("curl --header api_key=sk-secret-value")
        guard transaction.commands.first?.contains("[REDACTED]") == true else { fatalError("transaction command redaction failed") }
        transaction.github = GitHubTaskMetadata(
            repository: GitHubRepositoryBinding(
                owner: "fixture",
                repo: "repo",
                remoteName: "origin",
                remoteURL: "https://github.com/fixture/repo.git",
                defaultBranch: "main",
                repositoryID: "fixture-1"
            ),
            issueNumber: 123,
            issueTitle: "Status label",
            taskBranch: "ai-dev-one/issue-123-status-label",
            baseBranch: "main",
            autonomousMode: false
        )
        transaction.transition(to: .interrupted)
        store.upsert(transaction)
        let reloaded = TaskTransactionStore(fileURL: file).transaction(id: transaction.taskId)
        guard reloaded?.finalState == .interrupted,
              reloaded?.checkpointId == "checkpoint",
              reloaded?.github?.issueNumber == 123,
              reloaded?.github?.autonomousMode == false else { fatalError("transaction persistence failed") }
        print("transaction=PASS redaction=PASS persistence=PASS github-metadata=PASS")
    }
}
