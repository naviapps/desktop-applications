extension ApplicationSnapshot {
  struct NativeSnapshot: Codable {
    let identity: ApplicationProcessIdentity
    let identifier: ApplicationIdentifier?
    let displayName: String?
    let terminated: Bool

    var snapshot: ApplicationSnapshot {
      ApplicationSnapshot(
        identity: identity, identifier: identifier, displayName: displayName,
        isTerminated: terminated)
    }
  }
  var nativeSnapshot: NativeSnapshot {
    NativeSnapshot(
      identity: identity, identifier: identifier, displayName: displayName, terminated: isTerminated
    )
  }
  /// Validates recorded metadata against a fresh native snapshot in Rust.
  public func validationError(against actual: Self) throws -> ApplicationTargetValidationError? {
    struct Input: Encodable {
      let expected: NativeSnapshot
      let actual: NativeSnapshot
    }
    struct OptionalError: Decodable {
      let value: ApplicationTargetValidationError?
      init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value =
          container.decodeNil() ? nil : try container.decode(ApplicationTargetValidationError.self)
      }
    }
    return try NativeCore.query(
      2, Input(expected: nativeSnapshot, actual: actual.nativeSnapshot), as: OptionalError.self
    ).value
  }
}
