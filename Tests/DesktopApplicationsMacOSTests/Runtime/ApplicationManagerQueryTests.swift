import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerQueryTests: XCTestCase {
  func testRuntimeReturnsCurrentApplication() throws {
    let runtime = applicationRuntimeReturningCurrentApplication(
      FakeRuntimeRunningApplication(
        processIdentifier: 456,
        bundleIdentifier: "com.example.current",
        displayName: "Current"
      )
    )

    let application = try XCTUnwrap(runtime.currentApplication())

    assertApplicationSnapshot(
      application,
      processIdentifier: 456,
      bundleIdentifier: "com.example.current",
      displayName: "Current"
    )
  }

  func testRuntimeReturnsNilForMissingCurrentApplication() {
    let runtime = applicationRuntimeReturningCurrentApplication(nil)

    XCTAssertNil(runtime.currentApplication())
  }

  func testRuntimeReturnsNilForTerminatedCurrentApplication() {
    let runtime = applicationRuntimeReturningCurrentApplication(
      FakeRuntimeRunningApplication(isTerminated: true)
    )

    XCTAssertNil(runtime.currentApplication())
  }

  func testRuntimeReturnsNilForInvalidCurrentApplicationProcessIdentifier() {
    let runtime = applicationRuntimeReturningCurrentApplication(
      FakeRuntimeRunningApplication(processIdentifier: 0)
    )

    XCTAssertNil(runtime.currentApplication())
  }

  func testRuntimeReturnsNilForNegativeCurrentApplicationProcessIdentifier() {
    let runtime = applicationRuntimeReturningCurrentApplication(
      FakeRuntimeRunningApplication(processIdentifier: -1)
    )

    XCTAssertNil(runtime.currentApplication())
  }

  func testRuntimeReturnsRunningApplicationSnapshot() throws {
    let runtime = applicationRuntimeReturningRunningApplication(
      { processIdentifier in
        FakeRuntimeRunningApplication(
          processIdentifier: processIdentifier,
          bundleIdentifier: "com.example.running",
          displayName: "Running"
        )
      },
      for: 789
    )

    let application = try XCTUnwrap(runtime.runningApplication(processIdentifier: 789))

    assertApplicationSnapshot(
      application,
      processIdentifier: 789,
      bundleIdentifier: "com.example.running",
      displayName: "Running"
    )
  }

  func testRuntimeReturnsNilForMissingRunningApplication() {
    let runtime = applicationRuntimeReturningRunningApplication(nil, for: 789)

    XCTAssertNil(runtime.runningApplication(processIdentifier: 789))
  }

  func testRuntimeReturnsNilForInvalidRunningApplicationProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Invalid process identifier should not perform a live lookup."
    )

    XCTAssertNil(runtime.runningApplication(processIdentifier: pid_t(0)))
  }

  func testRuntimeReturnsNilForNegativeRunningApplicationProcessIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationLookup(
      "Negative process identifier should not perform a live lookup."
    )

    XCTAssertNil(runtime.runningApplication(processIdentifier: pid_t(-1)))
  }

  func testRuntimeReturnsNilWhenRunningApplicationProcessIdentifierDoesNotMatchRequest() {
    let runtime = applicationRuntimeReturningRunningApplication(
      FakeRuntimeRunningApplication(processIdentifier: 987),
      for: 789
    )

    XCTAssertNil(runtime.runningApplication(processIdentifier: 789))
  }

  func testRuntimeReturnsNilForTerminatedRunningApplication() {
    let runtime = applicationRuntimeReturningRunningApplication(
      { processIdentifier in
        FakeRuntimeRunningApplication(processIdentifier: processIdentifier, isTerminated: true)
      },
      for: 789
    )

    XCTAssertNil(runtime.runningApplication(processIdentifier: 789))
  }

  func testRuntimeReturnsRunningApplicationsMatchingBundleIdentifier() {
    let runtime = applicationRuntimeReturningRunningApplications([
      FakeRuntimeRunningApplication(processIdentifier: 0),
      FakeRuntimeRunningApplication(processIdentifier: -1),
      FakeRuntimeRunningApplication(processIdentifier: 123, displayName: "First"),
      FakeRuntimeRunningApplication(
        processIdentifier: 456,
        displayName: "Terminated",
        isTerminated: true
      ),
      FakeRuntimeRunningApplication(
        processIdentifier: 567,
        bundleIdentifier: nil,
        displayName: "Missing Bundle"
      ),
      FakeRuntimeRunningApplication(
        processIdentifier: 678,
        bundleIdentifier: "com.example.other",
        displayName: "Other"
      ),
      FakeRuntimeRunningApplication(processIdentifier: 789, displayName: "Second"),
    ])

    let applications = runtime.runningApplications(bundleIdentifier: " \(Self.bundleIdentifier)\n")

    XCTAssertEqual(applications.map(\.processIdentifier), [123, 789])
    XCTAssertEqual(
      applications.map(\.bundleIdentifier),
      [
        Self.bundleIdentifier,
        Self.bundleIdentifier,
      ])
    XCTAssertEqual(applications.map(\.displayName), ["First", "Second"])
    XCTAssertEqual(applications.map(\.isTerminated), [false, false])
  }

  func testRuntimeReturnsEmptyForMissingRunningApplications() {
    let runtime = applicationRuntimeReturningRunningApplications(
      [],
      for: "com.example.missing.app"
    )

    XCTAssertTrue(runtime.runningApplications(bundleIdentifier: "com.example.missing.app").isEmpty)
  }

  func testRuntimeReturnsEmptyForBlankBundleIdentifier() {
    let runtime = applicationRuntimeRejectingRunningApplicationsLookup(
      "Blank bundle identifier should not perform a live lookup."
    )

    XCTAssertTrue(runtime.runningApplications(bundleIdentifier: "   ").isEmpty)
  }

  func testRuntimeReturnsFirstUsableNameForMatchingRunningApplications() {
    let name = "  Localized 名  "
    let runtime = applicationRuntimeReturningRunningApplications([
      FakeRuntimeRunningApplication(processIdentifier: 0, displayName: "Invalid Process"),
      FakeRuntimeRunningApplication(
        processIdentifier: 123, displayName: "Terminated", isTerminated: true),
      FakeRuntimeRunningApplication(
        processIdentifier: 234, bundleIdentifier: "com.example.other", displayName: "Other"),
      FakeRuntimeRunningApplication(processIdentifier: 345, displayName: nil),
      FakeRuntimeRunningApplication(processIdentifier: 456, displayName: ""),
      FakeRuntimeRunningApplication(processIdentifier: 461, displayName: " \n"),
      FakeRuntimeRunningApplication(processIdentifier: 567, displayName: name),
      FakeRuntimeRunningApplication(processIdentifier: 678, displayName: "Second Usable"),
    ])

    XCTAssertEqual(
      runtime.runningDisplayName(bundleIdentifier: " \(Self.bundleIdentifier)\n"), name)
  }

  func testRuntimeReturnsNilWhenMatchingRunningApplicationsHaveNoName() {
    let runtime = applicationRuntimeReturningRunningApplications([
      FakeRuntimeRunningApplication(processIdentifier: 123, displayName: nil),
      FakeRuntimeRunningApplication(processIdentifier: 456, displayName: " \n"),
    ])

    XCTAssertNil(runtime.runningDisplayName(bundleIdentifier: Self.bundleIdentifier))
  }

  func testRuntimeReturnsFrontmostApplicationSnapshot() throws {
    let runtime = applicationRuntimeReturningFrontmostApplication(
      FakeRuntimeRunningApplication(
        processIdentifier: 321,
        bundleIdentifier: "com.example.frontmost",
        displayName: "Frontmost"
      )
    )

    let frontmost = try XCTUnwrap(runtime.frontmostApplication())

    assertApplicationSnapshot(
      frontmost,
      processIdentifier: 321,
      bundleIdentifier: "com.example.frontmost",
      displayName: "Frontmost"
    )
  }

  func testRuntimeReturnsNilForMissingFrontmostApplication() {
    let runtime = applicationRuntimeReturningFrontmostApplication(nil)

    XCTAssertNil(runtime.frontmostApplication())
  }

  func testRuntimeReturnsNilForTerminatedFrontmostApplication() {
    let runtime = applicationRuntimeReturningFrontmostApplication(
      FakeRuntimeRunningApplication(isTerminated: true)
    )

    XCTAssertNil(runtime.frontmostApplication())
  }

  func testRuntimeReturnsNilForInvalidFrontmostApplicationProcessIdentifier() {
    let runtime = applicationRuntimeReturningFrontmostApplication(
      FakeRuntimeRunningApplication(processIdentifier: 0)
    )

    XCTAssertNil(runtime.frontmostApplication())
  }

  func testRuntimeReturnsNilForNegativeFrontmostApplicationProcessIdentifier() {
    let runtime = applicationRuntimeReturningFrontmostApplication(
      FakeRuntimeRunningApplication(processIdentifier: -1)
    )

    XCTAssertNil(runtime.frontmostApplication())
  }

  func testRuntimeReturnsInstalledApplicationURL() {
    let expectedURL = URL(fileURLWithPath: "/Applications/Example.app")
    let runtime = applicationRuntimeReturningInstalledApplicationURL(expectedURL)

    XCTAssertEqual(
      runtime.installedApplicationURL(bundleIdentifier: " \(Self.bundleIdentifier)\n"),
      expectedURL
    )
  }

  func testRuntimeReturnsNilForMissingInstalledApplication() {
    let runtime = applicationRuntimeReturningInstalledApplicationURL(
      nil,
      for: "com.example.missing.app"
    )

    XCTAssertNil(runtime.installedApplicationURL(bundleIdentifier: "com.example.missing.app"))
  }

  func testRuntimeReturnsNilForBlankInstalledApplicationBundleIdentifier() {
    let runtime = applicationRuntimeRejectingInstalledApplicationLookup(
      "Blank bundle identifier should not perform a live lookup."
    )

    XCTAssertNil(runtime.installedApplicationURL(bundleIdentifier: "   "))
  }

  private static let bundleIdentifier = "com.example.app"

}
