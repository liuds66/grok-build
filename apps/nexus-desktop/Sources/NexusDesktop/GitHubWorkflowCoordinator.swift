import Foundation

/// Read-only UI projection of the persisted GitHub task. It deliberately
/// carries no credential or command payload.
struct GitHubWorkflowSnapshot {
    let transaction: TaskTransaction?
    let restoring: Bool
    let error: String?
    let activePollerCount: Int

    static let idle = GitHubWorkflowSnapshot(
        transaction: nil,
        restoring: false,
        error: nil,
        activePollerCount: 0
    )

    var taskID: String? { transaction?.taskId }
    var metadata: GitHubTaskMetadata? { transaction?.github }
}

/// Long-lived owner for desktop GitHub CI recovery. A task id can own at most
/// one monitor. App shutdown only stops local polling; explicit user cancel is
/// the sole operation that writes the cancelled terminal state.
final class GitHubWorkflowCoordinator {
    private let provider: GitHubProvider
    private let store: TaskTransactionStore
    private let pollInterval: TimeInterval
    private let retryIntervals: [TimeInterval]
    private let pollQueue = DispatchQueue(label: "cn.ai-dev-one.github-ci-poller", qos: .utility)
    private let lock = NSLock()

    private var monitoredTaskIDs: Set<String> = []
    private var inFlightTaskIDs: Set<String> = []
    private var scheduledPolls: [String: DispatchWorkItem] = [:]
    private var retryCounts: [String: Int] = [:]
    private var shuttingDown = false
    private var _pollerStartCount = 0

    var onUpdate: ((GitHubWorkflowSnapshot) -> Void)?

    init(
        provider: GitHubProvider,
        store: TaskTransactionStore = .shared,
        pollInterval: TimeInterval = 15,
        retryIntervals: [TimeInterval] = [5, 15, 30]
    ) {
        self.provider = provider
        self.store = store
        self.pollInterval = max(0.05, pollInterval)
        self.retryIntervals = retryIntervals.isEmpty ? [5, 15, 30] : retryIntervals.map { max(0.05, $0) }
    }

    deinit {
        stopForAppShutdown()
    }

    var activePollerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return monitoredTaskIDs.count
    }

    var pollerStartCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _pollerStartCount
    }

    /// Enumerates the existing TaskTransaction store; no second task database
    /// or View-owned cache is introduced.
    func restore() {
        lock.lock()
        shuttingDown = false
        lock.unlock()

        let githubTransactions = store.allTransactions().filter { $0.github != nil }
        let recoverable = githubTransactions.filter { transaction in
            guard let metadata = transaction.github else { return false }
            return !transaction.finalState.isTerminal && metadata.workflowState == .waitingCI
        }

        if let latest = githubTransactions.first {
            publish(transaction: latest, restoring: recoverable.contains(where: { $0.taskId == latest.taskId }))
        } else {
            publish(transaction: nil)
        }

        for transaction in recoverable {
            startMonitoring(taskID: transaction.taskId, restoring: true)
        }
    }

    /// Used by the existing GitHub task pipeline after PR creation. Persisting
    /// happens before the first network observation, so a crash cannot lose
    /// the repository/PR recovery anchor.
    func monitor(_ transaction: TaskTransaction) {
        guard transaction.github?.workflowState == .waitingCI,
              !transaction.finalState.isTerminal else { return }
        store.upsert(transaction, forcePersist: true)
        publish(transaction: transaction)
        startMonitoring(taskID: transaction.taskId, restoring: false)
    }

    /// Safe manual observation for a rerun of the same PR. It never pushes,
    /// creates a PR, or replays an Agent stage.
    func refreshNow(taskID: String) {
        guard let transaction = store.transaction(id: taskID),
              transaction.github?.workflowState == .waitingCI,
              !transaction.finalState.isTerminal else { return }
        startMonitoring(taskID: taskID, restoring: false)
        refresh(taskID: taskID, restoring: false)
    }

    func cancel(taskID: String) {
        stopMonitoring(taskID: taskID)
        guard var transaction = store.transaction(id: taskID),
              var metadata = transaction.github,
              metadata.workflowState == .waitingCI
                || metadata.workflowState == .ciFailed
                || metadata.workflowState == .repairingCI else { return }

        metadata.record(.cancelled)
        transaction.github = metadata
        _ = transaction.transition(to: .cancelled, cancellationSource: .user)
        transaction.agentStages.append("GitHub workflow cancelled: user")
        store.upsert(transaction, forcePersist: true)
        publish(transaction: transaction)
    }

    /// Cmd+Q/window close only tears down local timers. The persisted GitHub
    /// workflow remains waiting_ci and is reattached on the next launch.
    func stopForAppShutdown() {
        lock.lock()
        shuttingDown = true
        let workItems = Array(scheduledPolls.values)
        scheduledPolls.removeAll()
        monitoredTaskIDs.removeAll()
        inFlightTaskIDs.removeAll()
        retryCounts.removeAll()
        lock.unlock()
        workItems.forEach { $0.cancel() }
    }

    private func startMonitoring(taskID: String, restoring: Bool) {
        lock.lock()
        guard !shuttingDown, !monitoredTaskIDs.contains(taskID) else {
            lock.unlock()
            return
        }
        monitoredTaskIDs.insert(taskID)
        _pollerStartCount += 1
        lock.unlock()
        refresh(taskID: taskID, restoring: restoring)
    }

    private func refresh(taskID: String, restoring: Bool) {
        lock.lock()
        guard !shuttingDown,
              monitoredTaskIDs.contains(taskID),
              !inFlightTaskIDs.contains(taskID) else {
            lock.unlock()
            return
        }
        inFlightTaskIDs.insert(taskID)
        scheduledPolls.removeValue(forKey: taskID)
        lock.unlock()

        guard let transaction = store.transaction(id: taskID),
              let metadata = transaction.github,
              metadata.workflowState == .waitingCI,
              !transaction.finalState.isTerminal,
              let repository = metadata.githubRepository,
              let pullRequestNumber = metadata.pullRequestNumber else {
            finishInFlight(taskID: taskID)
            stopMonitoring(taskID: taskID)
            publish(transaction: store.transaction(id: taskID), error: "GitHub 恢复缺少仓库或 PR 标识")
            return
        }

        if restoring { publish(transaction: transaction, restoring: true) }
        provider.getPullRequest(repository: repository, number: pullRequestNumber) { [weak self] result in
            guard let self else { return }
            guard self.shouldAcceptCallback(taskID: taskID) else {
                self.finishInFlight(taskID: taskID)
                return
            }
            switch result {
            case .failure(let error):
                self.finishInFlight(taskID: taskID)
                self.scheduleRetry(taskID: taskID, error: error)
            case .success(let pullRequest):
                if pullRequest.merged {
                    self.finishInFlight(taskID: taskID)
                    self.persistRemoteTerminal(taskID: taskID, state: .mergedByHuman, pullRequest: pullRequest)
                    self.stopMonitoring(taskID: taskID)
                    return
                }
                guard pullRequest.state.uppercased() == "OPEN" else {
                    self.finishInFlight(taskID: taskID)
                    self.persistRemoteTerminal(taskID: taskID, state: .blocked, pullRequest: pullRequest)
                    self.stopMonitoring(taskID: taskID)
                    return
                }
                self.provider.getChecks(repository: repository, pullRequest: pullRequestNumber) { checksResult in
                    guard self.shouldAcceptCallback(taskID: taskID) else {
                        self.finishInFlight(taskID: taskID)
                        return
                    }
                    switch checksResult {
                    case .failure(let error):
                        self.finishInFlight(taskID: taskID)
                        self.scheduleRetry(taskID: taskID, error: error)
                    case .success(let checks):
                        self.provider.getWorkflowRuns(repository: repository, branch: metadata.taskBranch) { runsResult in
                            guard self.shouldAcceptCallback(taskID: taskID) else {
                                self.finishInFlight(taskID: taskID)
                                return
                            }
                            switch runsResult {
                            case .failure(let error):
                                // A failed run-list read is not an empty run
                                // list. Keep waiting_ci and retry instead of
                                // allowing stale PR check rows to masquerade
                                // as a successful, merge-ready workflow.
                                self.finishInFlight(taskID: taskID)
                                self.scheduleRetry(taskID: taskID, error: error)
                            case .success(let runs):
                                self.finishInFlight(taskID: taskID)
                                self.applyObservation(
                                    taskID: taskID,
                                    pullRequest: pullRequest,
                                    checks: checks,
                                    workflowRuns: runs
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyObservation(
        taskID: String,
        pullRequest: GitHubPullRequest,
        checks: [GitHubCIRun],
        workflowRuns: [GitHubCIRun]
    ) {
        guard shouldAcceptCallback(taskID: taskID),
              var transaction = store.transaction(id: taskID),
              var metadata = transaction.github,
              metadata.workflowState != .cancelled,
              !transaction.finalState.isTerminal else {
            stopMonitoring(taskID: taskID)
            return
        }

        let before = metadata
        let status = Self.aggregate(checks: checks, workflowRuns: workflowRuns)
        let currentRun = workflowRuns.first

        metadata.pullRequestURL = pullRequest.url
        metadata.pullRequestRef = pullRequest.headBranch
        metadata.ciRunId = currentRun?.id ?? checks.first?.id ?? metadata.ciRunId
        metadata.ciRunAttempt = currentRun?.attempt ?? metadata.ciRunAttempt
        metadata.ciCheckNames = Array(Set(checks.compactMap(\.checkName))).sorted()
        metadata.ciLastObservedState = status
        metadata.ciFinalState = status
        Self.appendMeaningfulObservations(checks + Array(workflowRuns.prefix(1)), to: &metadata)

        switch status {
        case .passed, .neutral, .skipped:
            metadata.workflowState = .readyForHumanMerge
            transaction.github = metadata
            if transaction.pipeline.states[.verifier] == .passed,
               transaction.pipeline.states[.reviewer] == .passed {
                _ = transaction.transition(to: .completed)
            }
        case .failed, .timedOut, .cancelled:
            metadata.workflowState = .ciFailed
        case .queued, .inProgress, .unknown:
            metadata.workflowState = .waitingCI
        }

        if metadata != before {
            metadata.updatedAt = Date()
            transaction.github = metadata
            store.upsert(transaction, forcePersist: true)
        }
        lock.lock()
        retryCounts[taskID] = 0
        lock.unlock()
        publish(transaction: transaction)

        if metadata.workflowState == .waitingCI {
            scheduleNextPoll(taskID: taskID, after: pollInterval)
        } else {
            stopMonitoring(taskID: taskID)
        }
    }

    private func persistRemoteTerminal(taskID: String, state: GitHubWorkflowState, pullRequest: GitHubPullRequest) {
        guard var transaction = store.transaction(id: taskID),
              var metadata = transaction.github,
              metadata.workflowState != .cancelled else { return }
        metadata.pullRequestURL = pullRequest.url
        metadata.pullRequestRef = pullRequest.headBranch
        metadata.record(state)
        transaction.github = metadata
        store.upsert(transaction, forcePersist: true)
        publish(transaction: transaction)
    }

    private func scheduleRetry(taskID: String, error: Error) {
        guard shouldAcceptCallback(taskID: taskID) else { return }
        lock.lock()
        let count = retryCounts[taskID, default: 0]
        retryCounts[taskID] = count + 1
        lock.unlock()
        let delay = retryIntervals[min(count, retryIntervals.count - 1)]
        publish(transaction: store.transaction(id: taskID), error: GitHubRedaction.text(error.localizedDescription, limit: 500))
        scheduleNextPoll(taskID: taskID, after: delay)
    }

    private func scheduleNextPoll(taskID: String, after delay: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.scheduledPolls.removeValue(forKey: taskID)
            let mayContinue = !self.shuttingDown && self.monitoredTaskIDs.contains(taskID)
            self.lock.unlock()
            if mayContinue { self.refresh(taskID: taskID, restoring: false) }
        }
        lock.lock()
        guard !shuttingDown,
              monitoredTaskIDs.contains(taskID),
              scheduledPolls[taskID] == nil else {
            lock.unlock()
            return
        }
        scheduledPolls[taskID] = item
        lock.unlock()
        pollQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func stopMonitoring(taskID: String) {
        lock.lock()
        let item = scheduledPolls.removeValue(forKey: taskID)
        monitoredTaskIDs.remove(taskID)
        inFlightTaskIDs.remove(taskID)
        retryCounts.removeValue(forKey: taskID)
        lock.unlock()
        item?.cancel()
    }

    private func finishInFlight(taskID: String) {
        lock.lock()
        inFlightTaskIDs.remove(taskID)
        lock.unlock()
    }

    private func shouldAcceptCallback(taskID: String) -> Bool {
        lock.lock()
        let accepted = !shuttingDown && monitoredTaskIDs.contains(taskID)
        lock.unlock()
        guard accepted,
              let transaction = store.transaction(id: taskID),
              transaction.github?.workflowState != .cancelled,
              transaction.finalState != .cancelled else { return false }
        return true
    }

    private func publish(transaction: TaskTransaction?, restoring: Bool = false, error: String? = nil) {
        let snapshot = GitHubWorkflowSnapshot(
            transaction: transaction,
            restoring: restoring,
            error: error,
            activePollerCount: activePollerCount
        )
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }

    private static func aggregate(checks: [GitHubCIRun], workflowRuns: [GitHubCIRun]) -> GitHubCIStatus {
        // `gh pr checks` can briefly expose a queued/cached check row while a
        // rerun is already in_progress. The newest branch workflow run carries
        // the run/attempt identity and is authoritative for lifecycle state;
        // check rows remain the detailed job evidence.
        if let latestRun = workflowRuns.first, latestRun.status != .unknown {
            return latestRun.status
        }
        let observations = checks
        guard !observations.isEmpty else { return .queued }
        if observations.contains(where: { $0.status == .failed || $0.status == .timedOut || $0.status == .cancelled }) {
            return .failed
        }
        if observations.allSatisfy({ $0.status == .passed || $0.status == .skipped || $0.status == .neutral }) {
            return .passed
        }
        if observations.contains(where: { $0.status == .inProgress }) { return .inProgress }
        if observations.contains(where: { $0.status == .queued }) { return .queued }
        return .unknown
    }

    private static func appendMeaningfulObservations(_ observations: [GitHubCIRun], to metadata: inout GitHubTaskMetadata) {
        for observation in observations {
            let duplicate = metadata.ciRuns.contains {
                $0.id == observation.id
                    && $0.attempt == observation.attempt
                    && $0.checkName == observation.checkName
                    && $0.status == observation.status
            }
            if !duplicate { metadata.append(observation) }
        }
    }
}
