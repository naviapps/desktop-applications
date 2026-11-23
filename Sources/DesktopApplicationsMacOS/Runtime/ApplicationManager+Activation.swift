import AppKit
import DesktopApplications

extension ApplicationManager {
  /// Activates the current application.
  public func activateCurrentApplication(
    options: NSApplication.ActivationOptions = []
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: currentApplicationLookupResult(),
      request: { Self.requestActivation(for: $0, options: options) }
    )
  }

  /// Activates a running application represented by a process snapshot.
  public func activateApplication(
    _ snapshot: ApplicationSnapshot,
    options: NSApplication.ActivationOptions = []
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matching: snapshot),
      request: { Self.requestActivation(for: $0, options: options) }
    )
  }

  /// Activates a running application matching the process identifier.
  public func activateApplication(
    processIdentifier: pid_t,
    options: NSApplication.ActivationOptions = []
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matchingProcessIdentifier: processIdentifier),
      request: { Self.requestActivation(for: $0, options: options) }
    )
  }

  /// Activates a running application matching the process identifier and expected bundle identifier.
  public func activateApplication(
    processIdentifier: pid_t,
    expectedBundleIdentifier: String,
    options: NSApplication.ActivationOptions = []
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(
        matchingProcessIdentifier: processIdentifier,
        expectedBundleIdentifier: expectedBundleIdentifier),
      request: { Self.requestActivation(for: $0, options: options) }
    )
  }

  /// Activates the first running application selected for the bundle identifier.
  public func activateApplication(
    bundleIdentifier: String,
    options: NSApplication.ActivationOptions = []
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matchingBundleIdentifier: bundleIdentifier),
      request: { Self.requestActivation(for: $0, options: options) }
    )
  }

  private static func requestActivation(
    for application: any ApplicationManagerRunningApplication,
    options: NSApplication.ActivationOptions
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    requestResult(
      isAccepted: application.activate(options: options),
      rejectedError: .requestRejected
    )
  }

}
