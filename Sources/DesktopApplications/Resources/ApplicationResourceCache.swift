import CDesktopApplications

/// An adapter-provided native installation, revision and resource variant.
/// Values are meaningful only on the originating platform and machine.
public struct ApplicationResourceIdentity: Sendable, Hashable, Codable {
  public let identifier: ApplicationIdentifier
  public let location: String
  public let revision: String
  public let variant: String

  public init(
    identifier: ApplicationIdentifier, location: String, revision: String, variant: String
  ) {
    self.identifier = identifier
    self.location = location
    self.revision = revision
    self.variant = variant
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identifier == rhs.identifier
      && lhs.location.utf8.elementsEqual(rhs.location.utf8)
      && lhs.revision.utf8.elementsEqual(rhs.revision.utf8)
      && lhs.variant.utf8.elementsEqual(rhs.variant.utf8)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(identifier)
    hasher.combineUTF8(location)
    hasher.combineUTF8(revision)
    hasher.combineUTF8(variant)
  }
}

/// Retains native values under Rust's bounded identities, generations and eviction
/// decisions. Confine each instance to its adapter's executor. Missing values are
/// retried; invalidation or replacement during a load discards its stale result.
public final class ApplicationResourceCache<Value> {
  private struct Action: Encodable {
    let action: String
    var resource: ApplicationResourceIdentity?
    var identifier: ApplicationIdentifier?
    var generation: UInt64?
  }
  private struct Transition: Decodable {
    let generation: UInt64?
    let evictedGenerations: [UInt64]
    let loadIsCurrent: Bool
  }
  private let owner: OpaquePointer
  private var values: [UInt64: Value] = [:]

  public init() {
    precondition(
      desktop_applications_abi_version() == DESKTOP_APPLICATIONS_ABI_VERSION,
      "Unsupported native DesktopApplications ABI")
    owner = desktop_applications_resource_cache_create()!
  }

  deinit { desktop_applications_resource_cache_destroy(owner) }

  public func value(for identity: ApplicationResourceIdentity, load: () -> Value?) throws -> Value?
  {
    let transition = try query(Action(action: "resolve", resource: identity))
    guard let generation = transition.generation else {
      throw DesktopApplicationsError.nativeFailure
    }
    if !transition.evictedGenerations.isEmpty {
      // Releasing evicted values can reenter the cache. Otherwise resolve has
      // already established the current generation on this executor.
      apply(transition)
      guard try canRetain(generation) else { return nil }
    }
    if let value = values[generation] { return value }
    guard let value = load() else { return nil }
    guard try query(Action(action: "admitLoad", generation: generation)).loadIsCurrent else {
      return nil
    }
    values[generation] = value
    return value
  }

  /// Invalidates every installation/variant of an identifier, or all resources.
  public func invalidate(identifier: ApplicationIdentifier? = nil) throws {
    apply(try query(Action(action: "invalidate", identifier: identifier)))
  }

  private func query(_ action: Action) throws -> Transition {
    try NativeCore.resourceCacheQuery(owner, action)
  }

  private func apply(_ transition: Transition) {
    guard !transition.evictedGenerations.isEmpty else { return }
    var retired: [Value] = []
    // Finish mutation before releasing objects whose deinitializers may reenter.
    for generation in transition.evictedGenerations {
      if let value = values.removeValue(forKey: generation) { retired.append(value) }
    }
    withExtendedLifetime(retired) {}
  }

  private func canRetain(_ generation: UInt64) throws -> Bool {
    try query(Action(action: "validateLoad", generation: generation)).loadIsCurrent
  }
}
