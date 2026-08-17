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
        transaction.transition(to: .interrupted)
        store.upsert(transaction)
        let reloaded = TaskTransactionStore(fileURL: file).transaction(id: transaction.taskId)
        guard reloaded?.finalState == .interrupted,
              reloaded?.checkpointId == "checkpoint" else { fatalError("transaction persistence failed") }
        print("transaction=PASS redaction=PASS persistence=PASS")
    }
}
