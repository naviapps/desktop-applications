import DesktopApplications

extension ApplicationManager {
  /// Requests hiding only after revalidating the recorded application process.
  public func hideApplication(_ snapshot: ApplicationSnapshot)
    -> ApplicationRequestResult<ApplicationOperationError>
  {
    Self.applicationRequestResult(
      fromApplicationLookupResult: runningApplication(matching: snapshot),
      request: { Self.requestResult(isAccepted: $0.requestHide(), rejectedError: .requestRejected) }
    )
  }
}
