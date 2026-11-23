import AppKit
import DesktopApplications

/// Provides AppKit-backed application runtime operations.
@MainActor
public struct ApplicationManager {
  let workspace: NSWorkspace
  let dependencies: ApplicationManagerDependencies

  /// Creates an AppKit-backed application runtime.
  public init(workspace: NSWorkspace = .shared) {
    self.init(workspace: workspace, dependencies: .live())
  }

  init(
    workspace: NSWorkspace = .shared,
    dependencies: ApplicationManagerDependencies
  ) {
    self.workspace = workspace
    self.dependencies = dependencies
  }

  static func requestResult<Failure: Error>(
    isAccepted: Bool,
    rejectedError: Failure
  ) -> ApplicationRequestResult<Failure> {
    isAccepted ? .requestAccepted : .failed(rejectedError)
  }
}
