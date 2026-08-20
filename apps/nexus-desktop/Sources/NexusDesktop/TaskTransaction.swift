import Foundation

enum TaskTransactionState: String, Codable {
    case created
    case planning
    case building
    case testing
    case reviewing
    case completed
    case failed
    case cancelled
    case interrupted
    case rolledBack = "rolled_back"

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted, .rolledBack:
            return true
        case .created, .planning, .building, .testing, .reviewing:
            return false
        }
    }
}

/// The only supported reasons for a task cancellation/interruption.  Keeping
/// this separate from the UI error text prevents a late runtime message (or a
/// browser/server cleanup message) from being mistaken for user intent.
enum TaskCancellationSource: String, Codable {
    case user
    case appShutdown = "app_shutdown"
    case coreCrash = "core_crash"
    case sessionSwitch = "session_switch"
    case workspaceChange = "workspace_change"
    case timeout
    case superseded
    case browserCleanup = "browser_cleanup"
    case devServerCleanup = "dev_server_cleanup"
    case runtimeDisconnect = "runtime_disconnect"
    case internalError = "internal"
    case unknown
}

enum AgentStageName: String, CaseIterable, Codable {
    case architect = "Architect"
    case builder = "Builder"
    case verifier = "Verifier"
    case reviewer = "Reviewer"
}

enum AgentStageState: String, Codable {
    case waiting
    case active
    case passed
    case failed
    case skipped
}

struct AgentPipelineSnapshot: Codable, Equatable {
    var states: [AgentStageName: AgentStageState]

    init(states: [AgentStageName: AgentStageState]? = nil) {
        self.states = states ?? Dictionary(uniqueKeysWithValues: AgentStageName.allCases.map { ($0, .waiting) })
    }
}

/// A strict, single-active-stage state machine. UI events may arrive out of
/// order, but they cannot make Builder/Verifier/Reviewer active early.
struct AgentPipelineStateMachine {
    private(set) var snapshot = AgentPipelineSnapshot()

    var activeStage: AgentStageName? {
        snapshot.states.first(where: { $0.value == .active })?.key
    }

    var canComplete: Bool {
        snapshot.states[.verifier] == .passed && snapshot.states[.reviewer] == .passed
    }

    mutating func reset() {
        snapshot = AgentPipelineSnapshot()
    }

    @discardableResult
    mutating func start(_ stage: AgentStageName) -> Bool {
        guard activeStage == nil,
              snapshot.states[stage] == .waiting,
              predecessorPassed(for: stage) else { return false }
        snapshot.states[stage] = .active
        return true
    }

    @discardableResult
    mutating func pass(_ stage: AgentStageName) -> Bool {
        guard snapshot.states[stage] == .active else { return false }
        snapshot.states[stage] = .passed
        return true
    }

    @discardableResult
    mutating func fail(_ stage: AgentStageName) -> Bool {
        guard snapshot.states[stage] == .active else { return false }
        snapshot.states[stage] = .failed
        for later in laterStages(after: stage) where snapshot.states[later] == .waiting {
            snapshot.states[later] = .skipped
        }
        return true
    }

    private func predecessorPassed(for stage: AgentStageName) -> Bool {
        guard let index = AgentStageName.allCases.firstIndex(of: stage), index > 0 else { return true }
        let predecessor = AgentStageName.allCases[index - 1]
        return snapshot.states[predecessor] == .passed
    }

    private func laterStages(after stage: AgentStageName) -> [AgentStageName] {
        guard let index = AgentStageName.allCases.firstIndex(of: stage) else { return [] }
        return Array(AgentStageName.allCases.dropFirst(index + 1))
    }
}

struct TaskTransaction: Codable, Identifiable {
    let taskId: String
    let sessionId: String
    let projectPath: String
    let checkpointId: String?
    let startedAt: Date
    var finishedAt: Date?
    var agentStages: [String]
    var toolCalls: [String]
    var fileChanges: [String]
    var commands: [String]
    var verification: [VerificationCheck]
    var cost: Double?
    var finalState: TaskTransactionState
    /// Persisted for auditability.  Older transaction files do not have this
    /// key, so decoding deliberately uses decodeIfPresent below.
    var cancellationSource: TaskCancellationSource?
    var pipeline: AgentPipelineSnapshot
    /// Optional GitHub workflow metadata.  Keeping it nullable preserves
    /// compatibility with local-only transactions and older JSON files.
    var github: GitHubTaskMetadata?

    var id: String { taskId }

    init(sessionId: String, projectPath: String, checkpointId: String? = nil) {
        self.taskId = UUID().uuidString.lowercased()
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.checkpointId = checkpointId
        self.startedAt = Date()
        self.finishedAt = nil
        self.agentStages = []
        self.toolCalls = []
        self.fileChanges = []
        self.commands = []
        self.verification = []
        self.cost = nil
        self.finalState = .created
        self.cancellationSource = nil
        self.pipeline = AgentPipelineSnapshot()
        self.github = nil
    }

    @discardableResult
    mutating func transition(
        to state: TaskTransactionState,
        cancellationSource: TaskCancellationSource? = nil
    ) -> Bool {
        // Local Agent completion is not the terminal result of a GitHub task
        // that is still waiting for remote verification.
        if state == .completed,
           github?.workflowState == .waitingCI || github?.workflowState == .ciFailed {
            return false
        }
        // A terminal result is immutable.  In particular, an authoritative
        // runtime `end` arriving after user cancel/Core crash must not turn the
        // transaction back into verification or completed.
        // Rollback is an explicit user action that is allowed to move a
        // failed/cancelled/interrupted task into the separate rolled_back
        // terminal state.  All other terminal states remain immutable so a
        // late runtime event cannot resurrect or rewrite the result.
        if finalState.isTerminal, state != .rolledBack { return false }
        if finalState == .rolledBack { return false }
        if state == .rolledBack {
            guard finalState == .failed || finalState == .cancelled || finalState == .interrupted else { return false }
            finalState = .rolledBack
            finishedAt = Date()
            return true
        }
        if state == .cancelled {
            // Cancellation is an explicit intent, never inferred from a
            // localized error string.  Keep legacy callers safe by recording
            // unknown rather than silently losing the audit reason.
            self.cancellationSource = cancellationSource ?? .unknown
        } else if state == .interrupted {
            self.cancellationSource = cancellationSource
        } else if state != .failed {
            self.cancellationSource = nil
        }
        finalState = state
        if state.isTerminal {
            finishedAt = Date()
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case taskId, sessionId, projectPath, checkpointId, startedAt, finishedAt
        case agentStages, toolCalls, fileChanges, commands, verification, cost
        case finalState, cancellationSource, pipeline, github
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decode(String.self, forKey: .taskId)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        checkpointId = try container.decodeIfPresent(String.self, forKey: .checkpointId)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        agentStages = try container.decode([String].self, forKey: .agentStages)
        toolCalls = try container.decode([String].self, forKey: .toolCalls)
        fileChanges = try container.decode([String].self, forKey: .fileChanges)
        commands = try container.decode([String].self, forKey: .commands)
        verification = try container.decode([VerificationCheck].self, forKey: .verification)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        finalState = try container.decode(TaskTransactionState.self, forKey: .finalState)
        cancellationSource = try container.decodeIfPresent(TaskCancellationSource.self, forKey: .cancellationSource)
        pipeline = try container.decode(AgentPipelineSnapshot.self, forKey: .pipeline)
        github = try container.decodeIfPresent(GitHubTaskMetadata.self, forKey: .github)
    }

    mutating func appendCommand(_ command: String) {
        let redacted = command
            .replacingOccurrences(of: #"(?i)(api[_-]?key|token|password)\s*[=:]\s*[^\s]+"#, with: "$1=[REDACTED]", options: .regularExpression)
            .replacingOccurrences(of: #"sk-[A-Za-z0-9_-]+"#, with: "[REDACTED]", options: .regularExpression)
        commands.append(redacted)
    }
}

final class TaskTransactionStore {
    static let shared = TaskTransactionStore()

    private let fileURL: URL
    private var transactions: [String: TaskTransaction] = [:]
    private let lock = NSLock()
    // Runtime text arrives token-by-token.  Persisting the whole audit file
    // synchronously for every token blocks AppKit's main thread and can make
    // a healthy task look frozen.  Keep the in-memory transaction exact, but
    // coalesce non-terminal disk writes; terminal transitions always flush.
    private var lastPersistedAt = Date.distantPast
    private let persistInterval: TimeInterval = 0.15
    private let persistedArrayLimit = 500

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let folder = support.appendingPathComponent("Nexus", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.fileURL = folder.appendingPathComponent("task-transactions.json")
        }
        load()
    }

    func load() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? decoder.decode([TaskTransaction].self, from: data) else {
            transactions = [:]
            return
        }
        transactions = Dictionary(uniqueKeysWithValues: values.map { ($0.taskId, $0) })
    }

    func upsert(_ transaction: TaskTransaction, forcePersist: Bool = false) {
        lock.lock()
        transactions[transaction.taskId] = transaction
        let now = Date()
        let shouldPersist = forcePersist
            || transaction.finalState.isTerminal
            || now.timeIntervalSince(lastPersistedAt) >= persistInterval
        guard shouldPersist else {
            lock.unlock()
            return
        }
        lastPersistedAt = now
        let values = Array(transactions.values)
            .sorted { $0.startedAt > $1.startedAt }
            .map { boundedForPersistence($0) }
        let data = try? encoder.encode(values)
        lock.unlock()
        if let data { try? data.write(to: fileURL, options: .atomic) }
    }

    private func boundedForPersistence(_ transaction: TaskTransaction) -> TaskTransaction {
        var bounded = transaction
        bounded.agentStages = Array(transaction.agentStages.suffix(persistedArrayLimit))
        bounded.toolCalls = Array(transaction.toolCalls.suffix(persistedArrayLimit))
        bounded.fileChanges = Array(transaction.fileChanges.suffix(persistedArrayLimit))
        bounded.commands = Array(transaction.commands.suffix(persistedArrayLimit))
        bounded.verification = Array(transaction.verification.suffix(persistedArrayLimit))
        return bounded
    }

    func transaction(id: String) -> TaskTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions[id]
    }

    /// Returns an immutable snapshot for cold-start recovery. Callers never
    /// receive the store's internal dictionary, so GitHub lifecycle recovery
    /// can enumerate non-terminal work without creating a second database.
    func allTransactions() -> [TaskTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// Test/live-acceptance cleanup is deliberately task-id scoped. It never
    /// clears the user's transaction database or unrelated session history.
    func remove(taskID: String) {
        lock.lock()
        transactions.removeValue(forKey: taskID)
        lastPersistedAt = Date()
        let values = Array(transactions.values)
            .sorted { $0.startedAt > $1.startedAt }
            .map { boundedForPersistence($0) }
        let data = try? encoder.encode(values)
        lock.unlock()
        if let data { try? data.write(to: fileURL, options: .atomic) }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
