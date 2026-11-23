/// Describes how an application termination request should be performed.
public enum ApplicationTerminationMode: Sendable, CaseIterable, Equatable, Hashable {
  /// Requests graceful application termination.
  case graceful
  /// Requests forced application termination.
  case forced
}
