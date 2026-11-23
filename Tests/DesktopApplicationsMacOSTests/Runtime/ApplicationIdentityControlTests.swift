import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationIdentityControlTests: XCTestCase {
  func testInvalidSnapshotsFailBeforeLookingUpTheProcess() {
    let cases: [(String, ApplicationSnapshot, ApplicationOperationError)] = [
      (
        "blank bundle identifier", applicationRuntimeSnapshot(bundleIdentifier: "   "),
        .invalidBundleIdentifier
      ),
      (
        "zero process identifier", applicationRuntimeSnapshot(processIdentifier: 0),
        .invalidProcessIdentifier
      ),
      (
        "negative process identifier", applicationRuntimeSnapshot(processIdentifier: -1),
        .invalidProcessIdentifier
      ),
      (
        "terminated snapshot", applicationRuntimeSnapshot(isTerminated: true),
        .applicationTerminated
      ),
    ]
    for (label, snapshot, error) in cases {
      let manager = applicationRuntimeRejectingRunningApplicationLookup(
        "Unexpected live process lookup for \(label).")
      XCTAssertEqual(manager.activateApplication(snapshot), .failed(error), "Activation: \(label)")
      XCTAssertEqual(
        manager.terminateApplication(snapshot), .failed(error), "Termination: \(label)")
    }
  }

  func testSnapshotControlChecksTheLiveProcessBeforeRequestingEffects() {
    let snapshot = applicationRuntimeSnapshot()
    let cases:
      [(
        String, ApplicationSnapshot, FakeRuntimeRunningApplication,
        ApplicationRequestResult<ApplicationOperationError>
      )] = [
        (
          "padded bundle identifier",
          applicationRuntimeSnapshot(bundleIdentifier: " com.example.app\n"),
          FakeRuntimeRunningApplication(processIdentifier: 456), .requestAccepted
        ),
        (
          "omitted bundle identifier", applicationRuntimeSnapshot(bundleIdentifier: nil),
          FakeRuntimeRunningApplication(processIdentifier: 456), .requestAccepted
        ),
        (
          "mismatched process identifier", snapshot,
          FakeRuntimeRunningApplication(processIdentifier: 999), .failed(.applicationNotFound)
        ),
        (
          "mismatched bundle identifier", snapshot,
          FakeRuntimeRunningApplication(
            processIdentifier: 456, bundleIdentifier: "com.example.other"),
          .failed(.applicationBundleIdentifierMismatch)
        ),
        (
          "unavailable live bundle identifier", snapshot,
          FakeRuntimeRunningApplication(processIdentifier: 456, bundleIdentifier: nil),
          .failed(.applicationBundleIdentifierUnavailable)
        ),
      ]
    for (label, snapshot, live, outcome) in cases {
      let manager = applicationRuntimeReturningRunningApplication(
        live, for: snapshot.processIdentifier)
      let accepted = outcome == .requestAccepted

      XCTAssertEqual(manager.activateApplication(snapshot), outcome, "Activation: \(label)")
      XCTAssertEqual(live.activationOptions, accepted ? [[]] : [], "Activation effects: \(label)")
      XCTAssertEqual(live.gracefulTerminationRequestCount, 0, "Activation effects: \(label)")
      XCTAssertEqual(live.forcedTerminationRequestCount, 0, "Activation effects: \(label)")

      XCTAssertEqual(manager.terminateApplication(snapshot), outcome, "Termination: \(label)")
      XCTAssertEqual(live.activationOptions, accepted ? [[]] : [], "Termination effects: \(label)")
      XCTAssertEqual(
        live.gracefulTerminationRequestCount, accepted ? 1 : 0, "Termination effects: \(label)")
      XCTAssertEqual(live.forcedTerminationRequestCount, 0, "Termination effects: \(label)")
    }
  }

  func testReusedPIDCannotActivateOrTerminateAnApplication() {
    let live = FakeRuntimeRunningApplication(processIdentifier: 456)
    live.startTime = 200
    let manager = applicationRuntimeReturningRunningApplication(live, for: 456)
    let recorded = ApplicationSnapshot(
      processIdentifier: 456, bundleIdentifier: live.bundleIdentifier, startTime: 100)
    XCTAssertEqual(manager.activateApplication(recorded), .failed(.processIdentityMismatch))
    XCTAssertEqual(manager.terminateApplication(recorded), .failed(.processIdentityMismatch))
    XCTAssertTrue(live.activationOptions.isEmpty)
    XCTAssertEqual(live.gracefulTerminationRequestCount, 0)
    XCTAssertEqual(live.forcedTerminationRequestCount, 0)
  }

  func testUnknownCreationMetadataNeverAuthorizesSnapshotControl() {
    let live = FakeRuntimeRunningApplication(processIdentifier: 456)
    let manager = applicationRuntimeReturningRunningApplication(live, for: 456)
    let unknown = ApplicationSnapshot(processIdentifier: 456)
    XCTAssertEqual(manager.activateApplication(unknown), .failed(.processIdentityUnavailable))
    XCTAssertEqual(
      manager.terminateApplication(unknown, mode: .forced), .failed(.processIdentityUnavailable))
    XCTAssertTrue(live.activationOptions.isEmpty)
    XCTAssertEqual(live.forcedTerminationRequestCount, 0)
  }

  func testDifferentIdentifierSpellingCannotAuthorizeProcessControl() {
    let live = FakeRuntimeRunningApplication(
      processIdentifier: 456, bundleIdentifier: "com.example.K")
    let manager = applicationRuntimeReturningRunningApplication(live, for: 456)
    let differentSpelling = "com.example.\u{212A}"

    XCTAssertEqual(
      manager.activateApplication(
        processIdentifier: 456, expectedBundleIdentifier: differentSpelling),
      .failed(.applicationBundleIdentifierMismatch))
    XCTAssertEqual(
      manager.terminateApplication(
        processIdentifier: 456, expectedBundleIdentifier: differentSpelling, mode: .forced),
      .failed(.applicationBundleIdentifierMismatch))
    assertActivationOptions(live, [])
    assertTerminationRequests(live, graceful: 0, forced: 0)
  }

  func testExactIdentifierStillRequiresTheSameProcessOnRecheck() {
    let recorded = FakeRuntimeRunningApplication(processIdentifier: 456)
    let replacement = FakeRuntimeRunningApplication(processIdentifier: 456)
    replacement.startTime = 2
    var lookups = 0
    let manager = applicationRuntimeReturningRunningApplication(
      { _ in
        defer { lookups += 1 }
        return lookups.isMultiple(of: 2) ? recorded : replacement
      }, for: 456)

    XCTAssertEqual(
      manager.activateApplication(
        processIdentifier: 456, expectedBundleIdentifier: "com.example.app"),
      .failed(.processIdentityMismatch))
    XCTAssertEqual(
      manager.terminateApplication(
        processIdentifier: 456, expectedBundleIdentifier: "com.example.app", mode: .forced),
      .failed(.processIdentityMismatch))
    for application in [recorded, replacement] {
      assertActivationOptions(application, [])
      assertTerminationRequests(application, graceful: 0, forced: 0)
    }
  }

  func testMatchingCreationMetadataPermitsNativeRequestAndPreservesRejection() {
    let live = FakeRuntimeRunningApplication(
      processIdentifier: 456, activationRequestAccepted: false)
    let manager = applicationRuntimeReturningRunningApplication(live, for: 456)
    let recorded = ApplicationSnapshot(
      processIdentifier: 456, bundleIdentifier: live.bundleIdentifier, startTime: live.startTime)
    XCTAssertEqual(manager.activateApplication(recorded), .failed(.requestRejected))
    XCTAssertEqual(live.activationOptions.count, 1)
    XCTAssertEqual(manager.terminateApplication(recorded), .requestAccepted)
    XCTAssertEqual(live.gracefulTerminationRequestCount, 1)
  }
}
