import Darwin
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
func assertRuntimeRunningApplication(
  _ application: any ApplicationManagerRunningApplication,
  matches expected: any ApplicationManagerRunningApplication,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  assertRuntimeApplicationFields(
    processIdentifier: application.processIdentifier,
    bundleIdentifier: application.bundleIdentifier,
    displayName: application.displayName,
    isTerminated: application.isTerminated,
    expectedProcessIdentifier: expected.processIdentifier,
    expectedBundleIdentifier: expected.bundleIdentifier,
    expectedDisplayName: expected.displayName,
    expectedIsTerminated: expected.isTerminated,
    file: file,
    line: line
  )
}

func assertApplicationSnapshot(
  _ snapshot: ApplicationSnapshot,
  processIdentifier: pid_t,
  bundleIdentifier: String?,
  displayName: String?,
  isTerminated: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  assertRuntimeApplicationFields(
    processIdentifier: snapshot.processIdentifier,
    bundleIdentifier: snapshot.bundleIdentifier,
    displayName: snapshot.displayName,
    isTerminated: snapshot.isTerminated,
    expectedProcessIdentifier: processIdentifier,
    expectedBundleIdentifier: bundleIdentifier,
    expectedDisplayName: displayName,
    expectedIsTerminated: isTerminated,
    file: file,
    line: line
  )
}

private func assertRuntimeApplicationFields(
  processIdentifier: pid_t,
  bundleIdentifier: String?,
  displayName: String?,
  isTerminated: Bool,
  expectedProcessIdentifier: pid_t,
  expectedBundleIdentifier: String?,
  expectedDisplayName: String?,
  expectedIsTerminated: Bool,
  file: StaticString,
  line: UInt
) {
  XCTAssertEqual(processIdentifier, expectedProcessIdentifier, file: file, line: line)
  XCTAssertEqual(bundleIdentifier, expectedBundleIdentifier, file: file, line: line)
  XCTAssertEqual(displayName, expectedDisplayName, file: file, line: line)
  XCTAssertEqual(isTerminated, expectedIsTerminated, file: file, line: line)
}
