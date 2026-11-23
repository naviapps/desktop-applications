/// Recorded metadata for an application process. It is never a live OS handle.
public struct ApplicationSnapshot: Sendable, Equatable, Hashable {
  public let identity: ApplicationProcessIdentity
  public let identifier: ApplicationIdentifier?
  public let displayName: String?
  public let isTerminated: Bool
  public var processIdentifier: Int32 { Int32(exactly: identity.processID) ?? 0 }
  public var bundleIdentifier: String? { identifier?.kind == .bundle ? identifier?.value : nil }

  /// Creates recorded metadata without OS lookup. A zero start token denotes
  /// unavailable creation metadata and cannot authorize snapshot control.
  public init(
    processIdentifier: Int32,
    bundleIdentifier: String? = nil,
    displayName: String? = nil,
    isTerminated: Bool = false,
    startTime: UInt64 = 0
  ) {
    self.init(
      identity: ApplicationProcessIdentity(
        processID: UInt32(exactly: processIdentifier) ?? 0, startTime: startTime),
      identifier: bundleIdentifier.map { ApplicationIdentifier(recordedKind: .bundle, value: $0) },
      displayName: displayName, isTerminated: isTerminated)
  }

  public init(
    identity: ApplicationProcessIdentity,
    identifier: ApplicationIdentifier?,
    displayName: String? = nil,
    isTerminated: Bool = false
  ) {
    self.identity = identity
    self.identifier = identifier
    self.displayName = displayName
    self.isTerminated = isTerminated
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.identity == rhs.identity, lhs.identifier == rhs.identifier,
      lhs.isTerminated == rhs.isTerminated
    else { return false }
    switch (lhs.displayName, rhs.displayName) {
    case (nil, nil): return true
    case (let lhs?, let rhs?): return lhs.utf8.elementsEqual(rhs.utf8)
    default: return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(identity)
    hasher.combine(identifier)
    hasher.combine(isTerminated)
    hasher.combine(displayName != nil)
    if let displayName { hasher.combineUTF8(displayName) }
  }
}
