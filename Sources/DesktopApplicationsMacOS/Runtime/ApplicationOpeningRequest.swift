import Synchronization

/// Arbitrates OS completion and task cancellation without retaining a cancelled
/// task's continuation until the OS callback arrives.
final class ApplicationOpeningRequest: Sendable {
  private enum State {
    case ready
    case waiting(CheckedContinuation<Bool?, Never>)
    case finished
  }

  private let state = Mutex(State.ready)

  /// Commits dispatch unless cancellation already completed this request.
  func begin(_ continuation: CheckedContinuation<Bool?, Never>) -> Bool {
    let shouldDispatch = state.withLock { state in
      switch state {
      case .ready:
        state = .waiting(continuation)
        return true
      case .finished:
        return false
      case .waiting:
        preconditionFailure("An opening request can only begin once.")
      }
    }
    if !shouldDispatch { continuation.resume(returning: nil) }
    return shouldDispatch
  }

  /// The first terminal result wins. Nil means cancellation; late or duplicate
  /// OS callbacks have no effect. Resume outside the lock to allow reentrancy.
  func finish(_ isAccepted: Bool?) {
    let continuation = state.withLock { state -> CheckedContinuation<Bool?, Never>? in
      defer { state = .finished }
      guard case .waiting(let continuation) = state else { return nil }
      return continuation
    }
    continuation?.resume(returning: isAccepted)
  }
}
