import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: \(message)") }
}

@discardableResult
private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

private final class RecoveryFixtureProvider: GitHubProvider {
    let backendName = "recovery-fixture"
    private(set) var authState: GitHubAuthState = .githubReady
    var autonomousMode = true

    var pullRequest: GitHubPullRequest
    var checks: [GitHubCIRun]
    var workflowRuns: [GitHubCIRun]
    var workflowRunsError: Error?
    private(set) var getPullRequestCount = 0
    private(set) var getChecksCount = 0
    private(set) var pushCount = 0
    private(set) var createPRCount = 0
    private(set) var commentCount = 0

    init(repository: GitHubRepositoryBinding, status: GitHubCIStatus, runID: String, attempt: Int) {
        workflowRunsError = nil
        pullRequest = GitHubPullRequest(
            number: 2,
            title: "Fixture PR",
            body: "Fixture",
            headBranch: "ai-dev-one/issue-1-github-remote-roles",
            baseBranch: "v0.5-dev",
            url: "https://github.com/\(repository.fullName)/pull/2",
            state: "OPEN",
            isDraft: false,
            merged: false
        )
        checks = [GitHubCIRun(
            id: runID,
            workflow: "Pull Request Verification",
            job: "Deterministic verification",
            checkName: "Deterministic verification",
            status: status,
            conclusion: status.rawValue,
            url: "https://github.com/\(repository.fullName)/actions/runs/\(runID)",
            failureKind: nil,
            evidence: nil,
            attempt: nil
        )]
        workflowRuns = [GitHubCIRun(
            id: runID,
            workflow: "Pull Request Verification",
            job: nil,
            checkName: nil,
            status: status,
            conclusion: status.rawValue,
            url: "https://github.com/\(repository.fullName)/actions/runs/\(runID)",
            failureKind: nil,
            evidence: nil,
            attempt: attempt
        )]
    }

    func set(status: GitHubCIStatus, runID: String, attempt: Int) {
        checks = checks.map {
            GitHubCIRun(id: runID, workflow: $0.workflow, job: $0.job, checkName: $0.checkName, status: status, conclusion: status.rawValue, url: $0.url, failureKind: nil, evidence: nil)
        }
        workflowRuns = workflowRuns.map {
            GitHubCIRun(id: runID, workflow: $0.workflow, job: nil, checkName: nil, status: status, conclusion: status.rawValue, url: $0.url, failureKind: nil, evidence: nil, attempt: attempt)
        }
    }

    func authenticate(completion: @escaping GitHubCompletion<GitHubAuthState>) { completion(.success(.githubReady)) }
    func getRepository(owner: String, repo: String, completion: @escaping GitHubCompletion<GitHubRepositoryBinding>) { completion(.failure(GitHubError.notFound("unused"))) }
    func getIssue(repository: GitHubRepositoryBinding, number: Int, completion: @escaping GitHubCompletion<GitHubIssue>) { completion(.failure(GitHubError.notFound("unused"))) }
    func listIssues(repository: GitHubRepositoryBinding, completion: @escaping GitHubCompletion<[GitHubIssue]>) { completion(.success([])) }
    func createBranch(name: String, from base: String, in workspace: URL, completion: @escaping GitHubCompletion<String>) { completion(.failure(GitHubError.unsafeRemoteAction("unexpected create branch"))) }
    func pushBranch(_ branch: String, remote: String, in workspace: URL, completion: @escaping GitHubCompletion<String>) { pushCount += 1; completion(.failure(GitHubError.unsafeRemoteAction("unexpected push"))) }
    func createPullRequest(repository: GitHubRepositoryBinding, head: String, base: String, title: String, body: String, completion: @escaping GitHubCompletion<GitHubPullRequest>) { createPRCount += 1; completion(.failure(GitHubError.unsafeRemoteAction("unexpected PR"))) }
    func getPullRequest(repository: GitHubRepositoryBinding, number: Int, completion: @escaping GitHubCompletion<GitHubPullRequest>) { getPullRequestCount += 1; completion(.success(pullRequest)) }
    func updatePullRequest(repository: GitHubRepositoryBinding, number: Int, title: String?, body: String?, completion: @escaping GitHubCompletion<GitHubPullRequest>) { completion(.failure(GitHubError.unsafeRemoteAction("unexpected update"))) }
    func getChecks(repository: GitHubRepositoryBinding, pullRequest: Int, completion: @escaping GitHubCompletion<[GitHubCIRun]>) { getChecksCount += 1; completion(.success(checks)) }
    func getWorkflowRuns(repository: GitHubRepositoryBinding, branch: String?, completion: @escaping GitHubCompletion<[GitHubCIRun]>) {
        if let workflowRunsError { completion(.failure(workflowRunsError)) }
        else { completion(.success(workflowRuns)) }
    }
    func getCheckLogs(repository: GitHubRepositoryBinding, runID: String, completion: @escaping GitHubCompletion<String>) { completion(.success("fixture")) }
    func addComment(repository: GitHubRepositoryBinding, issueOrPR: Int, body: String, completion: @escaping GitHubCompletion<Bool>) { commentCount += 1; completion(.failure(GitHubError.unsafeRemoteAction("unexpected comment"))) }
    func getDefaultBranch(repository: GitHubRepositoryBinding, completion: @escaping GitHubCompletion<String>) { completion(.success(repository.defaultBranch)) }
    func getRemoteHead(repository: GitHubRepositoryBinding, remote: String, branch: String, workspace: URL, completion: @escaping GitHubCompletion<String>) { completion(.success("fixture-sha")) }
}

private let repository = GitHubRepositoryBinding(
    owner: "liuds66",
    repo: "grok-build",
    remoteName: "origin",
    remoteURL: "https://github.com/liuds66/grok-build.git",
    defaultBranch: "v0.5-dev",
    repositoryID: "fixture-repository"
)

private func makeStore(_ name: String) -> (TaskTransactionStore, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ai-dev-one-ci-recovery-\(name)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (TaskTransactionStore(fileURL: root.appendingPathComponent("transactions.json")), root)
}

private func makeWaitingTransaction() -> TaskTransaction {
    var transaction = TaskTransaction(sessionId: "session-phase-3-7", projectPath: "/tmp/fixture", checkpointId: "checkpoint")
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
        issueTitle: "Fixture",
        taskBranch: "ai-dev-one/issue-1-github-remote-roles",
        baseBranch: "v0.5-dev",
        autonomousMode: true
    )
    metadata.localCommitSHA = "local-sha"
    metadata.remoteCommitSHA = "remote-sha"
    metadata.pullRequestNumber = 2
    metadata.pullRequestURL = "https://github.com/liuds66/grok-build/pull/2"
    metadata.pullRequestRef = metadata.taskBranch
    metadata.record(.waitingCI)
    transaction.github = metadata
    return transaction
}

@main
struct GitHubCIRecoveryHarness {
    static func main() {
        // CASE A: App shutdown preserves waiting_ci and all recovery anchors.
        let (storeA, rootA) = makeStore("quit")
        defer { try? FileManager.default.removeItem(at: rootA) }
        let waitingA = makeWaitingTransaction()
        storeA.upsert(waitingA, forcePersist: true)
        let providerA = RecoveryFixtureProvider(repository: repository, status: .inProgress, runID: "100", attempt: 1)
        let coordinatorA = GitHubWorkflowCoordinator(provider: providerA, store: storeA, pollInterval: 3600)
        coordinatorA.restore()
        expect(waitUntil { storeA.transaction(id: waitingA.taskId)?.github?.ciRunId == "100" }, "CASE A initial observation")
        expect(storeA.transaction(id: waitingA.taskId)?.github?.ciLastObservedState == .inProgress, "CASE A workflow run is authoritative")
        expect(coordinatorA.activePollerCount == 1, "CASE A exactly one poller")
        coordinatorA.stopForAppShutdown()
        let reloadedA = TaskTransactionStore(fileURL: rootA.appendingPathComponent("transactions.json"))
        let afterQuit = reloadedA.transaction(id: waitingA.taskId)
        expect(afterQuit?.finalState == .reviewing, "CASE A app quit is not cancellation")
        expect(afterQuit?.github?.workflowState == .waitingCI, "CASE A waiting_ci persists")
        expect(afterQuit?.github?.pullRequestNumber == 2, "CASE A same PR")

        // CASE B: CI may pass while the App is closed; restart only reattaches.
        let providerB = RecoveryFixtureProvider(repository: repository, status: .passed, runID: "100", attempt: 1)
        let coordinatorB = GitHubWorkflowCoordinator(provider: providerB, store: reloadedA, pollInterval: 3600)
        coordinatorB.restore()
        expect(waitUntil { reloadedA.transaction(id: waitingA.taskId)?.github?.workflowState == .readyForHumanMerge }, "CASE B ready for human merge")
        let recovered = reloadedA.transaction(id: waitingA.taskId)
        expect(recovered?.taskId == waitingA.taskId && recovered?.github?.pullRequestNumber == 2, "CASE B same task and PR")
        expect(providerB.pushCount == 0 && providerB.createPRCount == 0, "CASE B does not replay push/PR")
        coordinatorB.stopForAppShutdown()

        // CASE C/D/E: User cancel is terminal, persisted and immune to late PASS.
        let (storeC, rootC) = makeStore("cancel")
        defer { try? FileManager.default.removeItem(at: rootC) }
        let waitingC = makeWaitingTransaction()
        storeC.upsert(waitingC, forcePersist: true)
        let providerC = RecoveryFixtureProvider(repository: repository, status: .inProgress, runID: "110", attempt: 1)
        let coordinatorC = GitHubWorkflowCoordinator(provider: providerC, store: storeC, pollInterval: 3600)
        coordinatorC.restore()
        expect(waitUntil { coordinatorC.activePollerCount == 1 }, "CASE C poller started")
        coordinatorC.cancel(taskID: waitingC.taskId)
        let cancelled = storeC.transaction(id: waitingC.taskId)
        expect(cancelled?.finalState == .cancelled, "CASE C transaction cancelled")
        expect(cancelled?.cancellationSource == .user, "CASE C cancellation source user")
        expect(cancelled?.github?.workflowState == .cancelled, "CASE C GitHub workflow cancelled")
        expect(coordinatorC.activePollerCount == 0, "CASE C poller stopped")
        expect(providerC.pushCount == 0 && providerC.createPRCount == 0 && providerC.commentCount == 0, "CASE C no remote mutation")
        coordinatorC.stopForAppShutdown()

        let reloadedC = TaskTransactionStore(fileURL: rootC.appendingPathComponent("transactions.json"))
        let providerD = RecoveryFixtureProvider(repository: repository, status: .passed, runID: "110", attempt: 2)
        let coordinatorD = GitHubWorkflowCoordinator(provider: providerD, store: reloadedC, pollInterval: 3600)
        coordinatorD.restore()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(reloadedC.transaction(id: waitingC.taskId)?.github?.workflowState == .cancelled, "CASE D cancelled persists")
        expect(providerD.getPullRequestCount == 0 && providerD.getChecksCount == 0, "CASE D/E late PASS does not restart polling")
        coordinatorD.stopForAppShutdown()

        // CASE F/G: duplicate restore is idempotent; a rerun updates identity.
        let (storeF, rootF) = makeStore("rerun")
        defer { try? FileManager.default.removeItem(at: rootF) }
        let waitingF = makeWaitingTransaction()
        storeF.upsert(waitingF, forcePersist: true)
        let providerF = RecoveryFixtureProvider(repository: repository, status: .inProgress, runID: "200", attempt: 1)
        let coordinatorF = GitHubWorkflowCoordinator(provider: providerF, store: storeF, pollInterval: 3600)
        coordinatorF.restore()
        coordinatorF.restore()
        coordinatorF.restore()
        expect(waitUntil { storeF.transaction(id: waitingF.taskId)?.github?.ciRunId == "200" }, "CASE F first binding")
        expect(coordinatorF.pollerStartCount == 1 && coordinatorF.activePollerCount == 1, "CASE F one poller after three restores")
        expect(providerF.createPRCount == 0 && providerF.pushCount == 0, "CASE F no duplicate remote action")
        providerF.set(status: .inProgress, runID: "201", attempt: 2)
        coordinatorF.refreshNow(taskID: waitingF.taskId)
        expect(waitUntil { storeF.transaction(id: waitingF.taskId)?.github?.ciRunId == "201" }, "CASE G rerun id updated")
        expect(storeF.transaction(id: waitingF.taskId)?.github?.ciRunAttempt == 2, "CASE G rerun attempt updated")
        expect(storeF.transaction(id: waitingF.taskId)?.github?.pullRequestNumber == 2, "CASE G same PR")
        expect(coordinatorF.pollerStartCount == 1, "CASE G same workflow task")
        coordinatorF.stopForAppShutdown()

        // CASE H: a failed workflow-run read must remain waiting_ci.  Stale
        // PR check rows must never be promoted to merge-ready on an API error.
        let (storeH, rootH) = makeStore("run-error")
        defer { try? FileManager.default.removeItem(at: rootH) }
        let waitingH = makeWaitingTransaction()
        storeH.upsert(waitingH, forcePersist: true)
        let providerH = RecoveryFixtureProvider(repository: repository, status: .passed, runID: "300", attempt: 1)
        providerH.workflowRunsError = GitHubError.commandFailed("fixture workflow run error")
        let coordinatorH = GitHubWorkflowCoordinator(provider: providerH, store: storeH, pollInterval: 3600, retryIntervals: [0.05])
        coordinatorH.restore()
        expect(waitUntil { providerH.getPullRequestCount > 0 }, "CASE H attempted run read")
        expect(waitUntil { providerH.getPullRequestCount > 1 }, "CASE H retries run read")
        let afterRunError = storeH.transaction(id: waitingH.taskId)
        expect(afterRunError?.github?.workflowState == .waitingCI, "CASE H remains waiting_ci")
        expect(afterRunError?.finalState == .reviewing, "CASE H does not complete")
        coordinatorH.stopForAppShutdown()

        print("quit-recovery PASS")
        print("downtime-ci-pass PASS")
        print("user-cancel-no-remote-mutation PASS")
        print("cancel-persistence-late-pass PASS")
        print("duplicate-restore-single-poller PASS")
        print("rerun-identity-same-task PASS")
        print("workflow-run-error-retry PASS")
    }
}
