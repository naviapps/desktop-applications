/// An opaque process creation token, meaningful only on its source OS/machine.
public struct ApplicationProcessIdentity: Sendable, Equatable, Hashable, Codable {
  public let processID: UInt32
  public let startTime: UInt64
  private enum CodingKeys: String, CodingKey {
    case processID = "processId"
    case startTime
  }

  public init(processID: UInt32, startTime: UInt64) {
    self.processID = processID
    self.startTime = startTime
  }
}
