import DesktopApplications

extension ApplicationSnapshot {
  @MainActor
  init(runningApplication: any ApplicationManagerRunningApplication) {
    self.init(
      processIdentifier: runningApplication.processIdentifier,
      bundleIdentifier: runningApplication.bundleIdentifier,
      displayName: runningApplication.displayName,
      isTerminated: runningApplication.isTerminated,
      startTime: runningApplication.startTime
    )
  }
}
