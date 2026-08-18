import Foundation

/// The parent-task lifecycle is intentionally independent from the browser
/// verification session.  Browser resources may finish/clean up before the
/// runtime's authoritative `end` event; that is not cancellation.
enum TaskFinalizationState: String {
    case running
    case awaitingRuntimeEnd = "awaiting_runtime_end"
    case awaitingBrowser = "awaiting_browser"
    case reviewerActive = "reviewer_active"
    case completed
    case failed
    case cancelled
    case interrupted
}

struct TaskFinalizationTraceEvent: Codable, Equatable {
    let taskID: String
    let event: String
    let monotonicSeconds: Double
    let wallTime: Date
}

/// Small, deterministic coordinator for the final part of a task.  It is
/// deliberately free of AppKit, Process and BrowserVerification references so
/// the race contract can be tested without a live model.  Only explicit
/// cancellation/interrupt APIs can enter terminal cancelled/interrupted
/// states; cleanup and late runtime events are ignored once a terminal state
/// has been established.
final class TaskFinalizationCoordinator {
    let taskID: String
    private(set) var state: TaskFinalizationState = .running
    private(set) var runtimeEndReceived = false
    private(set) var browserVerificationPassed = false
    private(set) var reviewerStarted = false
    private(set) var reviewerPassed = false
    private(set) var cancellationSource: TaskCancellationSource?
    private(set) var trace: [TaskFinalizationTraceEvent] = []

    init(taskID: String) {
        self.taskID = taskID
        record("task_created")
    }

    var isTerminal: Bool {
        switch state {
        case .completed, .failed, .cancelled, .interrupted:
            return true
        case .running, .awaitingRuntimeEnd, .awaitingBrowser, .reviewerActive:
            return false
        }
    }

    /// Accept the authoritative runtime `end` exactly once.  The caller may
    /// receive this before or after browser verification; either ordering is
    /// valid, but neither ordering is allowed to cancel the parent task.
    @discardableResult
    func runtimeEnded() -> Bool {
        guard !isTerminal, !runtimeEndReceived else { return false }
        runtimeEndReceived = true
        state = browserVerificationPassed ? .reviewerActive : .awaitingBrowser
        record("runtime_end")
        return true
    }

    /// Marks Browser Verification PASS.  Closing the browser/server session
    /// is intentionally not represented here as a cancellation event.
    @discardableResult
    func browserPassed() -> Bool {
        guard !isTerminal, !browserVerificationPassed else { return false }
        browserVerificationPassed = true
        state = runtimeEndReceived ? .reviewerActive : .awaitingRuntimeEnd
        record("browser_verification_pass")
        return true
    }

    /// A failed browser gate is a task failure, not a cancellation.
    @discardableResult
    func browserFailed() -> Bool {
        guard !isTerminal else { return false }
        state = .failed
        record("browser_verification_fail")
        return true
    }

    var canStartReviewer: Bool {
        runtimeEndReceived && browserVerificationPassed && !isTerminal && !reviewerStarted
    }

    @discardableResult
    func startReviewer() -> Bool {
        guard canStartReviewer else { return false }
        reviewerStarted = true
        state = .reviewerActive
        record("reviewer_start")
        return true
    }

    @discardableResult
    func finishReviewer(passed: Bool) -> Bool {
        guard reviewerStarted, !isTerminal else { return false }
        reviewerPassed = passed
        state = passed ? .completed : .failed
        record(passed ? "reviewer_pass" : "reviewer_fail")
        return true
    }

    /// User cancellation is the only normal path into `cancelled`.  Calling
    /// this repeatedly is idempotent and cannot overwrite a completed task.
    @discardableResult
    func requestCancel(source: TaskCancellationSource) -> Bool {
        guard !isTerminal else { return false }
        guard source == .user || source == .appShutdown || source == .sessionSwitch || source == .workspaceChange || source == .timeout || source == .superseded else {
            return false
        }
        cancellationSource = source
        state = .cancelled
        record("cancel:\(source.rawValue)")
        return true
    }

    /// Core loss is an interruption, never a user cancellation.
    @discardableResult
    func interrupt(source: TaskCancellationSource = .coreCrash) -> Bool {
        guard !isTerminal else { return false }
        cancellationSource = source
        state = .interrupted
        record("interrupt:\(source.rawValue)")
        return true
    }

    @discardableResult
    func fail(reason: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        state = .failed
        let suffix = reason?.isEmpty == false ? ":\(reason!)" : ""
        record("fail\(suffix)")
        return true
    }

    /// Normal browser/session/server cleanup is explicitly a no-op for the
    /// parent task.  This method makes that contract visible to callers and
    /// gives the regression harness a concrete event to assert.
    func browserCleanupCompleted() {
        guard !isTerminal else { return }
        record("browser_cleanup")
    }

    func traceLines() -> [String] {
        trace.map { event in
            String(format: "task=%@ t=%.3f %@", event.taskID, event.monotonicSeconds, event.event)
        }
    }

    private func record(_ event: String) {
        trace.append(
            TaskFinalizationTraceEvent(
                taskID: taskID,
                event: event,
                monotonicSeconds: ProcessInfo.processInfo.systemUptime,
                wallTime: Date()
            )
        )
    }
}
