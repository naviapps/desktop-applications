/// Describes an application runtime lifecycle event.
public struct ApplicationEvent: Sendable, Equatable, Hashable {
  /// Identifies an application runtime lifecycle transition.
  public enum Lifecycle: String, Sendable, CaseIterable, Hashable, Codable {
    /// An application finished launching.
    case launched
    /// An application terminated.
    case terminated
    /// An application became active.
    case activated
    /// An application resigned active status.
    case deactivated
  }

  /// The lifecycle transition that occurred.
  public let lifecycle: Lifecycle
  /// The application snapshot captured when the lifecycle event occurred.
  public let application: ApplicationSnapshot

  /// Creates an application runtime event.
  public init(lifecycle: Lifecycle, application: ApplicationSnapshot) {
    self.lifecycle = lifecycle
    self.application = application
  }
}
