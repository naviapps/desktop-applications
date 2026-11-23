/// Failures at the native ownership or request boundary.
public enum DesktopApplicationsError: Error, Sendable {
  case nativeFailure
  case invalidInput(String)
}
