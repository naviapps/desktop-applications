/// A lookup key in its OS namespace. Identifiers never imply process identity.
public struct ApplicationIdentifier: Sendable, Equatable, Hashable, Codable {
  public enum Kind: String, Sendable, Codable { case bundle, executable, appUserModel }
  public let kind: Kind
  public let value: String

  public init(kind: Kind, value: String) throws {
    struct Input: Encodable {
      let kind: Kind
      let value: String
    }
    self = try NativeCore.query(1, Input(kind: kind, value: value))
  }

  package init(recordedKind: Kind, value: String) {
    kind = recordedKind
    self.value = value
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.kind == rhs.kind && lhs.value.utf8.elementsEqual(rhs.value.utf8)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(kind)
    hasher.combineUTF8(value)
  }
}

extension Hasher {
  // Keep Swift identity keys in the same byte namespace as the Rust core.
  mutating func combineUTF8(_ value: String) {
    var value = value
    value.withUTF8 { bytes in
      combine(bytes.count)
      combine(bytes: UnsafeRawBufferPointer(bytes))
    }
  }
}
