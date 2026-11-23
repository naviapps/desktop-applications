/// Describes why an application runtime request failed.
public enum ApplicationOperationError: Error, Sendable, Equatable, Hashable {
  /// The caller supplied a process identifier that cannot identify an application process.
  case invalidProcessIdentifier
  /// The caller supplied a bundle identifier that is blank after trimming whitespace.
  case invalidBundleIdentifier
  /// No running application matches the request.
  case applicationNotFound
  /// The requested application is already terminated.
  case applicationTerminated
  /// The matched application cannot expose the bundle identifier required for validation.
  case applicationBundleIdentifierUnavailable
  /// The matched application's bundle identifier does not equal the expected bundle identifier.
  case applicationBundleIdentifierMismatch
  /// The matched application rejected the request.
  case requestRejected
  /// Process creation metadata could not be obtained.
  case processIdentityUnavailable
  /// The recorded PID now identifies a different process instance.
  case processIdentityMismatch
}
