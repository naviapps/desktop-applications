import XCTest

func assertError<T: Error>(
  _ value: T,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertNotNil(value, file: file, line: line)
}

func assertSendable<T: Sendable>(
  _ value: T,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertNotNil(value, file: file, line: line)
}

func assertHashableSendable<T>(
  _: T.Type,
  _ value: T,
  file: StaticString = #filePath,
  line: UInt = #line
) where T: Hashable & Sendable {
  XCTAssertEqual(value, value, file: file, line: line)
  XCTAssertEqual(value.hashValue, value.hashValue, file: file, line: line)
}

func assertErrorHashableSendable<T>(
  _: T.Type,
  _ value: T,
  file: StaticString = #filePath,
  line: UInt = #line
) where T: Error & Hashable & Sendable {
  assertError(value, file: file, line: line)
  assertHashableSendable(T.self, value, file: file, line: line)
}
