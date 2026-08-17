import Foundation

enum CoreState: String {
    case stopped
    case starting
    case ready
    case disconnected
    case restarting
    case failed
}

enum CredentialLoadState: String {
    case loadingCredentials = "loading_credentials"
    case credentialsReady = "credentials_ready"
    case credentialsMissing = "credentials_missing"
    case credentialsDenied = "credentials_denied"
    case credentialsError = "credentials_error"
}

/// Bounded crash recovery: 1s, 2s, 5s, then a stable interrupted state.
final class CoreRecoveryCoordinator {
    static let retryDelays: [TimeInterval] = [1, 2, 5]

    private(set) var attempt = 0
    private var pending: DispatchWorkItem?

    func reset() {
        pending?.cancel()
        pending = nil
        attempt = 0
    }

    func schedule(
        retry: @escaping (_ attempt: Int) -> Void,
        exhausted: @escaping () -> Void
    ) {
        guard pending == nil else { return }
        guard attempt < Self.retryDelays.count else {
            exhausted()
            return
        }
        attempt += 1
        let currentAttempt = attempt
        let delay = Self.retryDelays[currentAttempt - 1]
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pending?.isCancelled == true {
                self.pending = nil
                return
            }
            self.pending = nil
            retry(currentAttempt)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
