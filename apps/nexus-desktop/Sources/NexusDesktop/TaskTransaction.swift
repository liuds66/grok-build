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
    var pipeline: AgentPipelineSnapshot

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
        self.pipeline = AgentPipelineSnapshot()
    }

    mutating func transition(to state: TaskTransactionState) {
        finalState = state
        if [.completed, .failed, .cancelled, .interrupted, .rolledBack].contains(state) {
            finishedAt = Date()
        }
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

    func upsert(_ transaction: TaskTransaction) {
        lock.lock()
        transactions[transaction.taskId] = transaction
        let values = Array(transactions.values).sorted { $0.startedAt > $1.startedAt }
        let data = try? encoder.encode(values)
        lock.unlock()
        if let data { try? data.write(to: fileURL, options: .atomic) }
    }

    func transaction(id: String) -> TaskTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions[id]
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
