import Darwin
import DesktopApplications

extension ApplicationManager {
  /// Requests termination of a running application represented by a process snapshot.
  public func terminateApplication(
    _ snapshot: ApplicationSnapshot,
    mode: ApplicationTerminationMode = .graceful
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matching: snapshot),
      request: { Self.requestTermination(for: $0, mode: mode) }
    )
  }

  /// Requests termination of a running application matching the process identifier.
  public func terminateApplication(
    processIdentifier: pid_t,
    mode: ApplicationTerminationMode = .graceful
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matchingProcessIdentifier: processIdentifier),
      request: { Self.requestTermination(for: $0, mode: mode) }
    )
  }

  /// Requests termination of a running application after validating its bundle identifier.
  public func terminateApplication(
    processIdentifier: pid_t,
    expectedBundleIdentifier: String,
    mode: ApplicationTerminationMode = .graceful
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(
        matchingProcessIdentifier: processIdentifier,
        expectedBundleIdentifier: expectedBundleIdentifier),
      request: { Self.requestTermination(for: $0, mode: mode) }
    )
  }

  /// Requests termination of the first running application selected for the bundle identifier.
  public func terminateApplication(
    bundleIdentifier: String,
    mode: ApplicationTerminationMode = .graceful
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matchingBundleIdentifier: bundleIdentifier),
      request: { Self.requestTermination(for: $0, mode: mode) }
    )
  }

  private static func requestTermination(
    for application: any ApplicationManagerRunningApplication,
    mode: ApplicationTerminationMode
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    let isAccepted =
      switch mode {
      case .graceful:
        application.requestGracefulTermination()
      case .forced:
        application.requestForcedTermination()
      }
    return requestResult(isAccepted: isAccepted, rejectedError: .requestRejected)
  }
}
