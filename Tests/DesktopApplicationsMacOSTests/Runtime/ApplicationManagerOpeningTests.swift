import AppKit
import DesktopApplications
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerOpeningTests: XCTestCase {

  func testOpenApplicationByBundleIdentifierMatchesDifferentCaseAfterTrimming() throws {
    let applicationURL = try temporaryApplicationBundleURL(bundleIdentifier: "Com.Example.App")
    defer { removeTemporaryItem(at: applicationURL) }
    let recorder = InstalledApplicationOpeningRequestRecorder(applicationURL: applicationURL)
    let runtime = recorder.runtimeRequestingResolvedApplicationOpening()

    XCTAssertEqual(
      runtime.openApplication(bundleIdentifier: Self.paddedBundleIdentifier),
      .requestAccepted
    )
    recorder.assertLookedUp(Self.bundleIdentifier)
    recorder.assertRequestedOpening(applicationURL)
  }

  func testOpenApplicationByBundleIdentifierValidatesResolvedURL() throws {
    let fileURL = try temporaryFileURL()
    defer { removeTemporaryItem(at: fileURL) }
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: fileURL,
      unexpectedOpenMessage: "Invalid resolved application URL should not request opening."
    ).runtimeRequestingResolvedApplicationOpening()

    assertFailedOpeningOutcome(
      runtime.openApplication(bundleIdentifier: Self.invalidBundleIdentifier),
      .invalidApplicationBundleURL
    )
  }

  func testOpenApplicationByBundleIdentifierReportsMissingApplication() {
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: nil,
      unexpectedOpenMessage: "Missing bundle identifier lookup should not request URL opening."
    ).runtimeRequestingResolvedApplicationOpening()

    assertFailedOpeningOutcome(
      runtime.openApplication(bundleIdentifier: Self.missingBundleIdentifier),
      .installedApplicationNotFound
    )
  }

  func testOpenApplicationByBundleIdentifierRejectsDifferentBundleAtRegisteredURL() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }

    // The fixture is a valid APPL declaring "com.example.app"; the lookup is stale.
    try await assertOpeningResolvedApplicationValidationError(
      applicationURL, .installedApplicationNotFound, bundleIdentifier: Self.missingBundleIdentifier)
  }

  func testOpenApplicationByBundleIdentifierKeepsValidLookupWithUnavailableIdentity() throws {
    let applicationURL = try temporaryApplicationBundleURL(bundleIdentifier: nil)
    defer { removeTemporaryItem(at: applicationURL) }

    let recorder = InstalledApplicationOpeningRequestRecorder(applicationURL: applicationURL)
    let runtime = recorder.runtimeRequestingResolvedApplicationOpening()
    XCTAssertEqual(
      runtime.openApplication(bundleIdentifier: Self.bundleIdentifier), .requestAccepted)
    recorder.assertRequestedOpening(applicationURL)
  }

  func testOpenApplicationByBundleIdentifierPrefersMacOSSpecificMetadata() async throws {
    let platformIdentifier = "com.example.platform"
    let applicationURL = try temporaryApplicationBundleURL(
      macOSBundleIdentifier: platformIdentifier)
    defer { removeTemporaryItem(at: applicationURL) }

    try await assertOpeningResolvedApplicationValidationError(
      applicationURL, .installedApplicationNotFound)

    let recorder = InstalledApplicationOpeningRequestRecorder(applicationURL: applicationURL)
    let runtime = recorder.runtimeRequestingResolvedApplicationOpening()
    XCTAssertEqual(runtime.openApplication(bundleIdentifier: platformIdentifier), .requestAccepted)
    recorder.assertRequestedOpening(applicationURL)
  }

  func testOpenApplicationByBundleIdentifierReportsRequestRejection() throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: applicationURL,
      result: false
    ).runtimeRequestingResolvedApplicationOpening()

    assertFailedOpeningOutcome(
      runtime.openApplication(bundleIdentifier: Self.bundleIdentifier),
      .requestRejected
    )
  }

  func testOpenApplicationAtURLRequestsApplicationOpening() throws {
    let applicationDirectory = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationDirectory) }

    let recorder = SynchronousOpeningRequestRecorder()
    let runtime = recorder.runtimeRequestingOpening()

    XCTAssertEqual(runtime.openApplication(at: applicationDirectory), .requestAccepted)
    recorder.assertRequestedOpening(applicationDirectory)
  }

  func testOpenApplicationAtURLReportsRequestRejection() throws {
    let applicationDirectory = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationDirectory) }

    let runtime = SynchronousOpeningRequestRecorder(result: false)
      .runtimeRequestingOpening()

    assertFailedOpeningOutcome(
      runtime.openApplication(at: applicationDirectory),
      .requestRejected
    )
  }

  func testAsyncOpenApplicationByBundleIdentifierMatchesDifferentCaseAfterTrimming() async throws {
    let applicationURL = try temporaryApplicationBundleURL(bundleIdentifier: "Com.Example.App")
    defer { removeTemporaryItem(at: applicationURL) }
    let configuration = NSWorkspace.OpenConfiguration()
    let recorder = InstalledApplicationOpeningRequestRecorder(applicationURL: applicationURL)
    let runtime = recorder.runtimeRequestingConfiguredResolvedApplicationOpening()

    let result = try await runtime.openApplication(
      bundleIdentifier: Self.paddedBundleIdentifier,
      configuration: configuration
    )

    XCTAssertEqual(result, .requestAccepted)
    recorder.assertLookedUp(Self.bundleIdentifier)
    recorder.assertRequestedOpening(applicationURL, configuration: configuration)
  }

  func testAsyncOpenApplicationByBundleIdentifierValidatesResolvedURL()
    async throws
  {
    let fileURL = try temporaryFileURL()
    defer { removeTemporaryItem(at: fileURL) }
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: fileURL,
      unexpectedOpenMessage: "Invalid resolved application URL should not request opening."
    ).runtimeRequestingConfiguredResolvedApplicationOpening()

    let result = try await runtime.openApplication(
      bundleIdentifier: Self.invalidBundleIdentifier,
      configuration: NSWorkspace.OpenConfiguration()
    )

    assertFailedOpeningOutcome(result, .invalidApplicationBundleURL)
  }

  func testAsyncOpenApplicationByBundleIdentifierReportsMissingApplication()
    async throws
  {
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: nil,
      unexpectedOpenMessage: "Missing bundle identifier lookup should not request URL opening."
    ).runtimeRequestingConfiguredResolvedApplicationOpening()

    let result = try await runtime.openApplication(
      bundleIdentifier: Self.missingBundleIdentifier,
      configuration: NSWorkspace.OpenConfiguration()
    )

    assertFailedOpeningOutcome(result, .installedApplicationNotFound)
  }

  func testAsyncOpenApplicationByBundleIdentifierReportsRequestRejection()
    async throws
  {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    let runtime = InstalledApplicationOpeningRequestRecorder(
      applicationURL: applicationURL,
      result: false
    ).runtimeRequestingConfiguredResolvedApplicationOpening()

    let result = try await runtime.openApplication(
      bundleIdentifier: Self.bundleIdentifier,
      configuration: NSWorkspace.OpenConfiguration()
    )

    assertFailedOpeningOutcome(result, .requestRejected)
  }

  func testAsyncOpenApplicationAtURLRequestsConfiguredApplicationOpening() async throws {
    let applicationDirectory = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationDirectory) }

    let configuration = NSWorkspace.OpenConfiguration()
    let recorder = ConfiguredOpeningRequestRecorder()
    let runtime = recorder.runtimeRequestingConfiguredApplicationOpening()

    let result = try await runtime.openApplication(
      at: applicationDirectory,
      configuration: configuration
    )

    XCTAssertEqual(result, .requestAccepted)
    recorder.assertRequestedOpening(applicationDirectory, configuration: configuration)
  }

  func testAsyncOpenApplicationAtURLReportsRequestRejection() async throws {
    let applicationDirectory = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationDirectory) }
    let runtime = ConfiguredOpeningRequestRecorder(result: false)
      .runtimeRequestingConfiguredApplicationOpening()

    let result = try await runtime.openApplication(
      at: applicationDirectory,
      configuration: NSWorkspace.OpenConfiguration()
    )

    assertFailedOpeningOutcome(result, .requestRejected)
  }

  private static let bundleIdentifier = "com.example.app"
  private static let invalidBundleIdentifier = "com.example.invalid"
  private static let missingBundleIdentifier = "com.example.missing"
  private static let paddedBundleIdentifier = " \(bundleIdentifier)\n"

}
