/// Represents the outcome of an application request with a typed failure reason.
public enum ApplicationRequestResult<Failure: Error> {
  /// The request was accepted.
  case requestAccepted
  /// The request was rejected or could not be attempted.
  case failed(Failure)
}

extension ApplicationRequestResult: Sendable where Failure: Sendable {}

extension ApplicationRequestResult: Equatable where Failure: Equatable {}

extension ApplicationRequestResult: Hashable where Failure: Hashable {}
