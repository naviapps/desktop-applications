import DesktopApplications
import XCTest

final class ApplicationSnapshotTests: XCTestCase {
  func testInitializerAssignsValues() {
    let snapshot = ApplicationSnapshot(
      processIdentifier: 123,
      bundleIdentifier: "com.example.app",
      displayName: "Example",
      isTerminated: false
    )

    XCTAssertEqual(snapshot.processIdentifier, 123)
    XCTAssertEqual(snapshot.bundleIdentifier, "com.example.app")
    XCTAssertEqual(snapshot.displayName, "Example")
    XCTAssertFalse(snapshot.isTerminated)
  }

  func testInitializerDoesNotValidateExplicitValues() {
    let snapshot = ApplicationSnapshot(
      processIdentifier: 0,
      bundleIdentifier: "   ",
      displayName: nil,
      isTerminated: true
    )

    XCTAssertEqual(snapshot.processIdentifier, 0)
    XCTAssertEqual(snapshot.bundleIdentifier, "   ")
    XCTAssertNil(snapshot.displayName)
    XCTAssertTrue(snapshot.isTerminated)
  }

  func testInitializerDefaultsUnavailableOptionalValues() {
    let snapshot = ApplicationSnapshot(
      processIdentifier: 123
    )

    XCTAssertEqual(snapshot.processIdentifier, 123)
    XCTAssertNil(snapshot.bundleIdentifier)
    XCTAssertNil(snapshot.displayName)
    XCTAssertFalse(snapshot.isTerminated)
  }

  func testEquatableMatchesAllFields() {
    let lhs = ApplicationSnapshot(
      processIdentifier: 1,
      bundleIdentifier: "com.example.app",
      displayName: "Example",
      isTerminated: false
    )
    let rhs = ApplicationSnapshot(
      processIdentifier: 1,
      bundleIdentifier: "com.example.app",
      displayName: "Example",
      isTerminated: false
    )

    XCTAssertEqual(lhs, rhs)
  }

  func testEquatableDistinguishesProcessIdentifier() {
    XCTAssertNotEqual(
      applicationProcessSnapshot(processIdentifier: 1),
      applicationProcessSnapshot(processIdentifier: 2)
    )
  }

  func testEquatableDistinguishesBundleIdentifier() {
    XCTAssertNotEqual(
      applicationProcessSnapshot(bundleIdentifier: "com.example.one"),
      applicationProcessSnapshot(bundleIdentifier: "com.example.two")
    )
    XCTAssertNotEqual(
      applicationProcessSnapshot(bundleIdentifier: "com.example.one"),
      applicationProcessSnapshot(bundleIdentifier: nil)
    )
  }

  func testEquatableDistinguishesDisplayName() {
    XCTAssertNotEqual(
      applicationProcessSnapshot(displayName: "One"),
      applicationProcessSnapshot(displayName: "Two")
    )
    XCTAssertNotEqual(
      applicationProcessSnapshot(displayName: "One"),
      applicationProcessSnapshot(displayName: nil)
    )
  }

  func testSnapshotAndEventEqualityPreserveDisplayNameSpelling() {
    let identity = ApplicationProcessIdentity(processID: 40, startTime: 100)
    let composed = ApplicationSnapshot(
      identity: identity, identifier: nil, displayName: "Caf\u{e9}")
    let decomposed = ApplicationSnapshot(
      identity: identity, identifier: nil, displayName: "Cafe\u{301}")
    XCTAssertNotEqual(composed, decomposed)
    XCTAssertEqual(Set([composed, decomposed]).count, 2)
    XCTAssertNotEqual(
      ApplicationEvent(lifecycle: .activated, application: composed),
      ApplicationEvent(lifecycle: .activated, application: decomposed))
  }

  func testEquatableDistinguishesTerminationState() {
    XCTAssertNotEqual(
      applicationProcessSnapshot(isTerminated: false),
      applicationProcessSnapshot(isTerminated: true)
    )
  }

  func testHashableUsesValueEquality() {
    let values: Set<ApplicationSnapshot> = [
      applicationProcessSnapshot(processIdentifier: 1),
      applicationProcessSnapshot(processIdentifier: 1),
      applicationProcessSnapshot(processIdentifier: 2),
    ]

    XCTAssertEqual(values.count, 2)
  }

}
