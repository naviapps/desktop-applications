import AppKit
import DesktopApplications

extension ApplicationSnapshot {
  /// Creates an application process snapshot from an AppKit running application.
  public init(runningApplication: NSRunningApplication) {
    self.init(
      processIdentifier: runningApplication.processIdentifier,
      bundleIdentifier: runningApplication.bundleIdentifier,
      displayName: runningApplication.localizedName,
      isTerminated: runningApplication.isTerminated,
      startTime: runningApplication.startTime
    )
  }
}
