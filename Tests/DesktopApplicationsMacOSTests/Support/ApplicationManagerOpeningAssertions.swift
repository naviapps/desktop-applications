import AppKit
import DesktopApplications
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

func assertFailedOpeningOutcome(
  _ result: ApplicationRequestResult<ApplicationLaunchError>,
  _ expectedError: ApplicationLaunchError,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  switch result {
  case .requestAccepted:
    XCTFail("Expected failed opening outcome. \(message())", file: file, line: line)
  case .failed(let error):
    XCTAssertEqual(error, expectedError, message(), file: file, line: line)
  }
}

@MainActor
func assertOpeningApplicationValidationError(
  bundleIdentifier: String,
  _ expectedError: ApplicationLaunchError,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let runtime = applicationRuntimeRejectingOpeningRequestDependencies(file: file, line: line)
  assertFailedOpeningOutcome(
    runtime.openApplication(bundleIdentifier: bundleIdentifier),
    expectedError,
    file: file,
    line: line
  )
  let result = try await runtime.openApplication(
    bundleIdentifier: bundleIdentifier,
    configuration: NSWorkspace.OpenConfiguration()
  )
  assertFailedOpeningOutcome(result, expectedError, file: file, line: line)
}

@MainActor
func assertOpeningApplicationValidationError(
  at url: URL,
  _ expectedError: ApplicationLaunchError,
  message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let runtime = applicationRuntimeRejectingOpeningRequestDependencies(file: file, line: line)
  assertFailedOpeningOutcome(
    runtime.openApplication(at: url),
    expectedError,
    message,
    file: file,
    line: line
  )
  let result = try await runtime.openApplication(
    at: url,
    configuration: NSWorkspace.OpenConfiguration()
  )
  assertFailedOpeningOutcome(result, expectedError, message, file: file, line: line)
}

@MainActor
func assertOpeningResolvedApplicationValidationError(
  _ url: URL,
  _ expectedError: ApplicationLaunchError,
  bundleIdentifier: String = "com.example.app",
  message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let runtime = applicationRuntimeResolvingApplicationBundleURL(
    url,
    for: bundleIdentifier,
    unexpectedOpenMessage:
      "Invalid resolved application bundle URL should not request opening.",
    file: file,
    line: line
  )
  assertFailedOpeningOutcome(
    runtime.openApplication(bundleIdentifier: bundleIdentifier),
    expectedError,
    message,
    file: file,
    line: line
  )
  let result = try await runtime.openApplication(
    bundleIdentifier: bundleIdentifier,
    configuration: NSWorkspace.OpenConfiguration()
  )
  assertFailedOpeningOutcome(result, expectedError, message, file: file, line: line)
}
