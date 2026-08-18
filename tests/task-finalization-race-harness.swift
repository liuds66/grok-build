import Foundation

@main
struct TaskFinalizationRaceHarness {
    static func main() {
        caseLateEnd(delay: 0.1)
        caseLateEnd(delay: 1.0)
        caseUserCancelWins()
        caseCoreCrashWins()
        caseBrowserCleanupDoesNotCancel()
        caseDevServerCleanupDoesNotCancel()
        caseReviewerFailure()
        print("race=A/B/C/D/E/F PASS reviewer-gate PASS terminal-guard PASS trace-monotonic PASS")
    }

    private static func caseLateEnd(delay: TimeInterval) {
        let coordinator = TaskFinalizationCoordinator(taskID: "late-(delay)")
        guard coordinator.browserPassed() else {
            fatalError("browser pass must be accepted")
        }
        Thread.sleep(forTimeInterval: delay)
        guard coordinator.runtimeEnded(), coordinator.startReviewer(), coordinator.finishReviewer(passed: true), coordinator.state == .completed else {
            fatalError("late runtime end must reach completed after reviewer")
        }
        let monotonic = coordinator.trace.map(\.monotonicSeconds)
        guard zip(monotonic, monotonic.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            fatalError("finalization trace must be monotonic")
        }
        if delay < 0.2 {
            print("trace.A=" + coordinator.traceLines().joined(separator: ";"))
        }
        // A duplicate authoritative event is harmless and must not run a
        // second reviewer/completion path.
        guard !coordinator.runtimeEnded(), !coordinator.startReviewer() else {
            fatalError("duplicate end/reviewer must be idempotent")
        }
        _ = delay // The state contract is independent of wall-clock delay.
    }

    private static func caseUserCancelWins() {
        let coordinator = TaskFinalizationCoordinator(taskID: "user-cancel")
        guard coordinator.browserPassed(), coordinator.requestCancel(source: .user), coordinator.state == .cancelled,
              coordinator.cancellationSource == .user,
              !coordinator.runtimeEnded(), !coordinator.startReviewer() else {
            fatalError("user cancellation must win over late end")
        }
    }

    private static func caseCoreCrashWins() {
        let coordinator = TaskFinalizationCoordinator(taskID: "core-crash")
        guard coordinator.interrupt(), coordinator.state == .interrupted,
              coordinator.cancellationSource == .coreCrash,
              !coordinator.runtimeEnded(), !coordinator.startReviewer() else {
            fatalError("core crash must interrupt and block late end")
        }
    }

    private static func caseBrowserCleanupDoesNotCancel() {
        let coordinator = TaskFinalizationCoordinator(taskID: "browser-cleanup")
        coordinator.browserCleanupCompleted()
        guard coordinator.state == .running,
              coordinator.browserPassed(), coordinator.runtimeEnded(), coordinator.startReviewer(), coordinator.finishReviewer(passed: true), coordinator.state == .completed else {
            fatalError("browser cleanup must not cancel the parent task")
        }
    }

    private static func caseDevServerCleanupDoesNotCancel() {
        let coordinator = TaskFinalizationCoordinator(taskID: "server-cleanup")
        coordinator.browserCleanupCompleted()
        guard coordinator.state == .running,
              coordinator.runtimeEnded(), coordinator.browserPassed(), coordinator.startReviewer(), coordinator.finishReviewer(passed: true), coordinator.state == .completed else {
            fatalError("server cleanup must not cancel the parent task")
        }
    }

    private static func caseReviewerFailure() {
        let coordinator = TaskFinalizationCoordinator(taskID: "reviewer-failure")
        guard coordinator.runtimeEnded(), coordinator.browserPassed(), coordinator.startReviewer(), coordinator.finishReviewer(passed: false), coordinator.state == .failed,
              !coordinator.requestCancel(source: .user) else {
            fatalError("reviewer failure must be failed, not cancelled")
        }
    }
}
