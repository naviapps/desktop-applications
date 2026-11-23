/// Describes why launching an application failed.
public enum ApplicationLaunchError: Error, Sendable, Equatable, Hashable {
  /// The application opening request received a URL that is not a valid application bundle.
  case invalidApplicationBundleURL
  /// The bundle identifier is blank after trimming whitespace.
  case invalidBundleIdentifier
  /// No installed application matches the bundle identifier.
  case installedApplicationNotFound
  /// No application bundle exists at the requested URL.
  case applicationBundleNotFound
  /// The underlying opening request was rejected.
  case requestRejected
}
