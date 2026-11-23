import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerTerminationTests: XCTestCase {
  func testTerminateApplicationByProcessIdentifierTerminatesMatchingApplication() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.terminateApplication(processIdentifier: 123)

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationByProcessIdentifierForceTerminatesMatchingApplication() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.terminateApplication(
      processIdentifier: 123,
      mode: .forced
    )

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationBySnapshotUsesProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    let result = runtime.terminateApplication(snapshot)

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationBySnapshotForceTerminatesMatchingApplication() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    let result = runtime.terminateApplication(snapshot, mode: .forced)

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationBySnapshotReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      gracefulTerminationRequestAccepted: false
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationBySnapshotReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      forcedTerminationRequestAccepted: false
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.terminateApplication(snapshot, mode: .forced),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationBySnapshotTrimsBundleIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot(bundleIdentifier: " com.example.app\n")

    XCTAssertEqual(runtime.terminateApplication(snapshot), .requestAccepted)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testTerminateApplicationBySnapshotRejectsBlankBundleIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Blank bundle identifier should not perform a live lookup."
    )
    let snapshot = applicationRuntimeSnapshot(bundleIdentifier: "   ")

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.invalidBundleIdentifier)
    )
  }

  func testTerminateApplicationBySnapshotRejectsInvalidProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Invalid process identifier should not perform a live lookup."
    )
    let snapshot = applicationRuntimeSnapshot(processIdentifier: 0)

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testTerminateApplicationBySnapshotRejectsNegativeProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Negative process identifier should not perform a live lookup."
    )
    let snapshot = applicationRuntimeSnapshot(processIdentifier: -1)

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testTerminateApplicationBySnapshotRejectsMismatchedRunningApplicationBundleIdentifier() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      bundleIdentifier: "com.example.other"
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.applicationBundleIdentifierMismatch)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationBySnapshotRejectsMissingRunningApplicationBundleIdentifier() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      bundleIdentifier: nil
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.applicationBundleIdentifierUnavailable)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationBySnapshotRejectsMismatchedRunningApplicationProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 789)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot()

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.applicationNotFound)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationBySnapshotAllowsMissingSnapshotBundleIdentifier() {
    let application = FakeRuntimeRunningApplication(
      processIdentifier: 456,
      bundleIdentifier: "com.example.app"
    )
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 456)
    let snapshot = applicationRuntimeSnapshot(bundleIdentifier: nil)

    XCTAssertEqual(runtime.terminateApplication(snapshot), .requestAccepted)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testTerminateApplicationBySnapshotRejectsTerminatedSnapshot() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Terminated snapshot should not perform a live lookup."
    )
    let snapshot = applicationRuntimeSnapshot(isTerminated: true)

    XCTAssertEqual(
      runtime.terminateApplication(snapshot),
      .failed(.applicationTerminated)
    )
  }

  func testTerminateApplicationByProcessIdentifierRejectsMissingApplication() {
    let runtime = applicationRuntimeReturningRunningApplication(nil, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 123),
      .failed(.applicationNotFound)
    )
  }

  func testTerminateApplicationByProcessIdentifierRejectsInvalidProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Invalid process identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 0),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testTerminateApplicationByProcessIdentifierRejectsNegativeProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Negative process identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: -1),
      .failed(.invalidProcessIdentifier)
    )
  }

  func testTerminateApplicationByProcessIdentifierRejectsTerminatedApplication() {
    let application = FakeRuntimeRunningApplication(isTerminated: true)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 123),
      .failed(.applicationTerminated)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationByProcessIdentifierRejectsMismatchedRunningProcessIdentifier() {
    let application = FakeRuntimeRunningApplication(processIdentifier: 456)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 123),
      .failed(.applicationNotFound)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationByProcessIdentifierReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(gracefulTerminationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 123),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationByProcessIdentifierReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(forcedTerminationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(processIdentifier: 123, mode: .forced),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationByProcessIdentifierAndExpectedBundleIdentifierTerminatesMatch() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.terminateApplication(
      processIdentifier: 123,
      expectedBundleIdentifier: " com.example.app\n"
    )

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testTerminateApplicationByProcessIdentifierAndExpectedBundleIdentifierForwardsMode() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    let result = runtime.terminateApplication(
      processIdentifier: 123,
      expectedBundleIdentifier: "com.example.app",
      mode: .forced
    )

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsBlankBundle() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Blank bundle identifier should not perform a live lookup."
    )

    XCTAssertEqual(
      runtime.terminateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "   "
      ),
      .failed(.invalidBundleIdentifier)
    )
  }

  func testTerminateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsMismatch() {
    let application = FakeRuntimeRunningApplication(bundleIdentifier: "com.example.other")
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "com.example.app"
      ),
      .failed(.applicationBundleIdentifierMismatch)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationByProcessIdentifierAndExpectedBundleIdentifierRejectsMissingBundle()
  {
    let application = FakeRuntimeRunningApplication(bundleIdentifier: nil)
    let runtime = applicationRuntimeReturningRunningApplication(application, for: 123)

    XCTAssertEqual(
      runtime.terminateApplication(
        processIdentifier: 123,
        expectedBundleIdentifier: "com.example.app"
      ),
      .failed(.applicationBundleIdentifierUnavailable)
    )
    assertTerminationRequests(application, graceful: 0, forced: 0)
  }

  func testTerminateApplicationByBundleIdentifierTrimsInput() {
    let terminatedApplication = FakeRuntimeRunningApplication(isTerminated: true)
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplications(
      [terminatedApplication, application],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup."
    )

    let result = runtime.terminateApplication(bundleIdentifier: " com.example.app\n")

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(terminatedApplication, graceful: 0, forced: 0)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationByBundleIdentifierForceTerminatesMatchingApplication() {
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplications(
      [application],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup."
    )

    let result = runtime.terminateApplication(
      bundleIdentifier: "com.example.app",
      mode: .forced
    )

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationByBundleIdentifierReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(gracefulTerminationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplications(
      [application],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.terminateApplication(bundleIdentifier: "com.example.app"),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testForceTerminateApplicationByBundleIdentifierReportsTerminationRequestRejection() {
    let application = FakeRuntimeRunningApplication(forcedTerminationRequestAccepted: false)
    let runtime = applicationRuntimeReturningRunningApplications(
      [application],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup."
    )

    XCTAssertEqual(
      runtime.terminateApplication(bundleIdentifier: "com.example.app", mode: .forced),
      .failed(.requestRejected)
    )
    assertTerminationRequests(application, graceful: 0, forced: 1)
  }

  func testTerminateApplicationByBundleIdentifierSkipsInvalidCandidates() {
    let invalidProcessIdentifierApplication = FakeRuntimeRunningApplication(processIdentifier: 0)
    let terminatedApplication = FakeRuntimeRunningApplication(isTerminated: true)
    let missingBundleIdentifierApplication = FakeRuntimeRunningApplication(bundleIdentifier: nil)
    let mismatchedApplication = FakeRuntimeRunningApplication(bundleIdentifier: "com.example.other")
    let application = FakeRuntimeRunningApplication()
    let runtime = applicationRuntimeReturningRunningApplications(
      [
        invalidProcessIdentifierApplication,
        terminatedApplication,
        missingBundleIdentifierApplication,
        mismatchedApplication,
        application,
      ],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup.")

    let result = runtime.terminateApplication(bundleIdentifier: "com.example.app")

    XCTAssertEqual(result, .requestAccepted)
    assertTerminationRequests(invalidProcessIdentifierApplication, graceful: 0, forced: 0)
    assertTerminationRequests(terminatedApplication, graceful: 0, forced: 0)
    assertTerminationRequests(missingBundleIdentifierApplication, graceful: 0, forced: 0)
    assertTerminationRequests(mismatchedApplication, graceful: 0, forced: 0)
    assertTerminationRequests(application, graceful: 1, forced: 0)
  }

  func testTerminateApplicationByBundleIdentifierRejectsBlankInput() {
    let runtime = applicationRuntimeRejectingBundleIdentifierLookups()

    XCTAssertEqual(
      runtime.terminateApplication(bundleIdentifier: "   "),
      .failed(.invalidBundleIdentifier)
    )
  }

  func testTerminateApplicationByBundleIdentifierRejectsMissingApplication() {
    let invalidProcessIdentifierApplication = FakeRuntimeRunningApplication(processIdentifier: 0)
    let terminatedApplication = FakeRuntimeRunningApplication(isTerminated: true)
    let missingBundleIdentifierApplication = FakeRuntimeRunningApplication(bundleIdentifier: nil)
    let mismatchedApplication = FakeRuntimeRunningApplication(bundleIdentifier: "com.example.other")
    let runtime = applicationRuntimeReturningRunningApplications(
      [
        invalidProcessIdentifierApplication,
        terminatedApplication,
        missingBundleIdentifierApplication,
        mismatchedApplication,
      ],
      unexpectedProcessLookupMessage:
        "Bundle identifier termination should not perform a process lookup.")

    XCTAssertEqual(
      runtime.terminateApplication(bundleIdentifier: "com.example.app"),
      .failed(.applicationNotFound)
    )
    assertTerminationRequests(invalidProcessIdentifierApplication, graceful: 0, forced: 0)
    assertTerminationRequests(terminatedApplication, graceful: 0, forced: 0)
    assertTerminationRequests(missingBundleIdentifierApplication, graceful: 0, forced: 0)
    assertTerminationRequests(mismatchedApplication, graceful: 0, forced: 0)
  }

}
