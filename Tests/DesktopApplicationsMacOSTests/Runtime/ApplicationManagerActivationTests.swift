import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerActivationTests: XCTestCase {
  func testActivateCurrentApplicationActivatesCurrentApplication() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningCurrentApplication(
      application,
      unexpectedProcessLookupMessage:
        "Current application activation should not perform a process lookup."
    )

    let result = runtime.activateCurrentApplication(options: [.activateAllWindows])

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [.activateAllWindows])
  }

  func testActivateCurrentApplicationRejectsMissingApplication() {
    let runtime = applicationRuntimeReturningCurrentApplication(
      nil,
      unexpectedProcessLookupMessage:
        "Current application activation should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.activateCurrentApplication(),
      .failed(.applicationNotFound)
    )
  }

  func testActivateCurrentApplicationRejectsInvalidProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 0)
    let runtime = applicationRuntimeReturningCurrentApplication(
      application,
      unexpectedProcessLookupMessage:
        "Current application activation should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.activateCurrentApplication(),
      .failed(.invalidProcessIdentifier)
    )
    assertActivationOptions(application, [])
  }

  func testActivateCurrentApplicationRejectsTerminatedApplication() {
    let application = FakeRuntimeRunningApplication(isTerminated: true)
    let runtime = applicationRuntimeReturningCurrentApplication(
      application,
      unexpectedProcessLookupMessage:
        "Current application activation should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.activateCurrentApplication(),
      .failed(.applicationTerminated)
    )
    assertActivationOptions(application, [])
  }

  func testActivateCurrentApplicationReportsActivationRequestRejection() {
    let application = FakeRuntimeRunningApplication(activationRequestAccepted: false)
    let runtime = applicationRuntimeReturningCurrentApplication(
      application,
      unexpectedProcessLookupMessage:
        "Current application activation should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.activateCurrentApplication(),
      .failed(.requestRejected)
    )
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationByProcessIdentifierActivatesMatchingApplication() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.activateApplication(
      processIdentifier: 123,
      options: [.activateAllWindows]
    )

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [.activateAllWindows])
  }

  func testActivateApplicationBySnapshotUsesProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    let result = runtime.activateApplication(snapshot)

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationBySnapshotForwardsOptions() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    let result = runtime.activateApplication(snapshot, options: [.activateAllWindows])

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [.activateAllWindows])
  }

  func testActivateApplicationBySnapshotReportsActivationRequestRejection() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      activationRequestAccepted: false
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.activateApplication(snapshot),
      .failed(.requestRejected)
    )
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationByProcessIdentifierRejectsMissingApplication() {
    let runtime = applicationRuntimeReturningRunningApplication(nil, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 123),
      .failed(.applicationNotFound)
    )
  }

  func testActivateApplicationByProcessIdentifierRejectsInvalidProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Invalid process identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 0),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testActivateApplicationByProcessIdentifierRejectsNegativeProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Negative process identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: -1),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testActivateApplicationByProcessIdentifierRejectsMismatchedLiveProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 999)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 123),
      .failed(.applicationNotFound)
    )
    assertActivationOptions(application, [])
  }

  func testActivateApplicationByProcessIdentifierRejectsTerminatedApplication() {
    let application = FakeRuntimeRunningApplication(isTerminated: true)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 123),
      .failed(.applicationTerminated)
    )
    assertActivationOptions(application, [])
  }

  func testActivateApplicationByProcessIdentifierReportsActivationRequestRejection() {
    let application = FakeRuntimeRunningApplication(activationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 123),
      .failed(.requestRejected)
    )
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationByProcessIdentifierAndExpectedBundleIdentifierActivatesMatch() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 123,
      bundleIdentifier: "com.example.app"
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.activateApplication(
      processIdentifier: 123,
      expectedBundleIdentifier: " com.example.app\n",
      options: [.activateAllWindows]
    )

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [.activateAllWindows])
  }

  func testActivateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsBlankBundle() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Blank expected bundle identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.activateApplication(processIdentifier: 123, expectedBundleIdentifier: "   "),
      .failed(.invalidBundleIdentifier)
    )
  }

  func testActivateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsMismatch() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 123,
      bundleIdentifier: "com.example.other"
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "com.example.app"
      ),
      .failed(.applicationBundleIdentifierMismatch)
    )
    assertActivationOptions(application, [])
  }

  func testActivateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsMissingBundle() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 123, bundleIdentifier: nil)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "com.example.app"
      ),
      .failed(.applicationBundleIdentifierUnavailable)
    )
    assertActivationOptions(application, [])
  }

  func testActivateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsTerminated() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 123,
      bundleIdentifier: "com.example.app",
      isTerminated: true
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.activateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "com.example.app"
      ),
      .failed(.applicationTerminated)
    )
    assertActivationOptions(application, [])
  }

  func testActivateApplicationByBundleIdentifierTrimsInput() {
    let invalidApplication = FakeRuntimeRunningApplication(processIdentifier: 0)
    let terminatedApplication = FakeRuntimeRunningApplication(isTerminated: true)
    let applicationBundleIdentifierUnavailableApplication = FakeRuntimeRunningApplication(
      bundleIdentifier: nil)
    let mismatchedApplication = FakeRuntimeRunningApplication(bundleIdentifier: "com.example.other")
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplications(
      [
        invalidApplication,
        terminatedApplication,
        applicationBundleIdentifierUnavailableApplication,
        mismatchedApplication,
        application,
      ],
      unexpectedProcessLookupMessage:
        "Bundle identifier activation should not perform a process lookup.")

    let result = runtime.activateApplication(bundleIdentifier: " com.example.app\n")

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(invalidApplication, [])
    assertActivationOptions(terminatedApplication, [])
    assertActivationOptions(applicationBundleIdentifierUnavailableApplication, [])
    assertActivationOptions(mismatchedApplication, [])
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationByBundleIdentifierForwardsOptions() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplications(
      [application],
      unexpectedProcessLookupMessage:
        "Bundle identifier activation should not perform a process lookup."
    )

    let result = runtime.activateApplication(
      bundleIdentifier: "com.example.app",
      options: [.activateAllWindows]
    )

    XCTAssertEqual(result, .requestAccepted)
    assertActivationOptions(application, [.activateAllWindows])
  }

  func testActivateApplicationByBundleIdentifierReportsActivationRequestRejection() {
    let application = FakeRuntimeRunningApplication(activationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplications(
      [application],
      unexpectedProcessLookupMessage:
        "Bundle identifier activation should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.activateApplication(bundleIdentifier: "com.example.app"),
      .failed(.requestRejected)
    )
    assertActivationOptions(application, [[]])
  }

  func testActivateApplicationByBundleIdentifierRejectsBlankInput() {
    let runtime = applicationRuntimeRejectingBundleIdentifierLookups()

    XCTAssertEqual(
      runtime.activateApplication(bundleIdentifier: "   "),
      .failed(.invalidBundleIdentifier)
    )
  }

  func testActivateApplicationByBundleIdentifierRejectsMissingApplication() {
    let invalidProcessIdentifierApplication = FakeRuntimeRunningApplication(processIdentifier: 0)
    let terminatedApplication = FakeRuntimeRunningApplication(isTerminated: true)
    let mismatchedApplication = FakeRuntimeRunningApplication(bundleIdentifier: "com.example.other")
    let runtime = applicationRuntimeReturningRunningApplications(
      [
        invalidProcessIdentifierApplication,
        terminatedApplication,
        mismatchedApplication,
      ],
      unexpectedProcessLookupMessage:
        "Bundle identifier activation should not perform a process lookup.")

    XCTAssertEqual(
      runtime.activateApplication(bundleIdentifier: "com.example.app"),
      .failed(.applicationNotFound)
    )
    assertActivationOptions(invalidProcessIdentifierApplication, [])
    assertActivationOptions(terminatedApplication, [])
    assertActivationOptions(mismatchedApplication, [])
  }

}
