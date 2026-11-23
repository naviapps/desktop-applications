/// A complete application snapshot for one sample from a polling adapter.
public struct ApplicationState: Sendable, Equatable, Hashable {
  public static let empty = Self(applications: [], frontmost: nil)

  public let applications: [ApplicationSnapshot]
  /// The foreground process identity, when it is part of this sample.
  public let frontmost: ApplicationProcessIdentity?

  public init(applications: [ApplicationSnapshot], frontmost: ApplicationProcessIdentity?) {
    self.applications = applications
    self.frontmost = frontmost
  }

  /// Validates two samples and derives ordered lifecycle transitions in Rust.
  /// Use the returned state as the previous sample at the next polling interval.
  public func reconcile(_ current: Self) throws -> ApplicationReconciliation {
    struct Input: Encodable {
      let previous: NativeState
      let current: NativeState
    }
    struct Result: Decodable {
      struct Event: Decodable {
        let lifecycle: ApplicationEvent.Lifecycle
        let application: ApplicationSnapshot.NativeSnapshot
      }
      let state: NativeState
      let events: [Event]
    }
    let result: Result = try NativeCore.query(
      3, Input(previous: nativeState, current: current.nativeState))
    return ApplicationReconciliation(
      state: Self(
        applications: result.state.applications.map(\.snapshot), frontmost: result.state.frontmost),
      events: result.events.map {
        ApplicationEvent(lifecycle: $0.lifecycle, application: $0.application.snapshot)
      })
  }

  private struct NativeState: Codable {
    let applications: [ApplicationSnapshot.NativeSnapshot]
    let frontmost: ApplicationProcessIdentity?
  }

  private var nativeState: NativeState {
    NativeState(applications: applications.map(\.nativeSnapshot), frontmost: frontmost)
  }
}

/// The normalized sample and events derived from a pair of application states.
public struct ApplicationReconciliation: Sendable, Equatable, Hashable {
  public let state: ApplicationState
  public let events: [ApplicationEvent]
}
