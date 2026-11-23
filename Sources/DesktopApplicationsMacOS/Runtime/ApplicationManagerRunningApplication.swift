import AppKit

/// Provides the live operations DesktopApplications can request from a running application.
@MainActor
protocol ApplicationManagerRunningApplication {
  var processIdentifier: pid_t { get }
  var bundleIdentifier: String? { get }
  var displayName: String? { get }
  var isTerminated: Bool { get }
  var startTime: UInt64 { get }

  func activate(options: NSApplication.ActivationOptions) -> Bool
  func requestGracefulTermination() -> Bool
  func requestForcedTermination() -> Bool
  func requestHide() -> Bool
}

extension NSRunningApplication: ApplicationManagerRunningApplication {
  nonisolated var startTime: UInt64 {
    guard let launchDate else { return 0 }
    let microseconds = (launchDate.timeIntervalSince1970 * 1_000_000).rounded()
    guard microseconds.isFinite, microseconds > 0, microseconds < Double(UInt64.max) else {
      return 0
    }
    return UInt64(microseconds)
  }

  var displayName: String? {
    localizedName
  }

  func requestGracefulTermination() -> Bool {
    terminate()
  }

  func requestForcedTermination() -> Bool {
    forceTerminate()
  }

  func requestHide() -> Bool { hide() }
}
