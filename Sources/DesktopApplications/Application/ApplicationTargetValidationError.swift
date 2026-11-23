/// A typed reason a recorded process cannot be used for a native operation.
public enum ApplicationTargetValidationError: String, Error, Sendable, Decodable {
  case invalidIdentifier, identityUnavailable, targetChanged
  case invalidProcessID = "invalidProcessId"
  case identifierUnavailable, identifierMismatch, terminated, duplicateProcess
}
