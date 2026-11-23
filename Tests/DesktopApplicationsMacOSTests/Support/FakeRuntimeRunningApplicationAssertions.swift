import AppKit
import XCTest

@MainActor
func assertActivationOptions(
  _ application: FakeRuntimeRunningApplication,
  _ expectedOptions: [NSApplication.ActivationOptions],
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(application.activationOptions, expectedOptions, file: file, line: line)
}

@MainActor
func assertTerminationRequests(
  _ application: FakeRuntimeRunningApplication,
  graceful expectedGracefulRequestCount: Int,
  forced expectedForcedRequestCount: Int,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(
    application.gracefulTerminationRequestCount,
    expectedGracefulRequestCount,
    file: file,
    line: line
  )
  XCTAssertEqual(
    application.forcedTerminationRequestCount,
    expectedForcedRequestCount,
    file: file,
    line: line
  )
}
