import AppKit
import DesktopApplications

@testable import DesktopApplicationsMacOS

@MainActor
final class FakeRuntimeRunningApplication: ApplicationManagerRunningApplication {
  var startTime: UInt64 = 1
  var processIdentifier: pid_t
  var bundleIdentifier: String?
  var displayName: String?
  var isTerminated: Bool
  var activationRequestAccepted: Bool
  var gracefulTerminationRequestAccepted: Bool
  var forcedTerminationRequestAccepted: Bool
  private(set) var activationOptions: [NSApplication.ActivationOptions] = []
  private(set) var gracefulTerminationRequestCount = 0
  private(set) var forcedTerminationRequestCount = 0

  init(
    processIdentifier: pid_t = 123,
    bundleIdentifier: String? = "com.example.app",
    displayName: String? = "Example",
    isTerminated: Bool = false,
    activationRequestAccepted: Bool = true,
    gracefulTerminationRequestAccepted: Bool = true,
    forcedTerminationRequestAccepted: Bool = true
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.isTerminated = isTerminated
    self.activationRequestAccepted = activationRequestAccepted
    self.gracefulTerminationRequestAccepted = gracefulTerminationRequestAccepted
    self.forcedTerminationRequestAccepted = forcedTerminationRequestAccepted
  }

  func activate(options: NSApplication.ActivationOptions) -> Bool {
    activationOptions.append(options)
    return activationRequestAccepted
  }

  func requestGracefulTermination() -> Bool {
    gracefulTerminationRequestCount += 1
    return gracefulTerminationRequestAccepted
  }

  func requestForcedTermination() -> Bool {
    forcedTerminationRequestCount += 1
    return forcedTerminationRequestAccepted
  }

  func requestHide() -> Bool { true }
}
