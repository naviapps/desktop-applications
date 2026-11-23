import CDesktopApplications
import Foundation

enum NativeCore {
  static func query<Input: Encodable, Output: Decodable>(
    _ operation: UInt32, _ input: Input, as _: Output.Type = Output.self
  ) throws -> Output {
    guard desktop_applications_abi_version() == DESKTOP_APPLICATIONS_ABI_VERSION else {
      throw DesktopApplicationsError.nativeFailure
    }
    let data = try JSONEncoder().encode(input)
    let owner = data.withUnsafeBytes {
      desktop_applications_query(operation, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
    }
    return try consume(owner)
  }

  static func resourceCacheQuery<Input: Encodable, Output: Decodable>(
    _ cache: OpaquePointer, _ input: Input
  ) throws -> Output {
    let data = try JSONEncoder().encode(input)
    let owner = data.withUnsafeBytes {
      desktop_applications_resource_cache_query(
        cache, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
    }
    return try consume(owner)
  }

  private static func consume<Output: Decodable>(_ owner: OpaquePointer?) throws -> Output {
    guard let owner else { throw DesktopApplicationsError.nativeFailure }
    defer { desktop_applications_buffer_free(owner) }
    var count = 0
    guard let pointer = desktop_applications_buffer_data(owner, &count) else {
      throw DesktopApplicationsError.nativeFailure
    }
    let result = try JSONDecoder().decode(
      Response<Output>.self, from: Data(bytes: pointer, count: count))
    if let error = result.error { throw DesktopApplicationsError.invalidInput(error) }
    guard let value = result.value else { throw DesktopApplicationsError.nativeFailure }
    return value
  }

  private struct Response<Value: Decodable>: Decodable {
    let value: Value?
    let error: String?
    enum CodingKeys: String, CodingKey { case value, error }
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      error = try container.decodeIfPresent(String.self, forKey: .error)
      value = container.contains(.value) ? try container.decode(Value.self, forKey: .value) : nil
    }
  }
}
