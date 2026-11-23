import AppKit
import DesktopApplications
import DesktopApplicationsMacOS
import XCTest

final class DesktopApplicationsMacOSPublicAPITests: XCTestCase {
  @MainActor
  func testQueriesAndInvalidRequestsAreUsableWithoutTestableImport() {
    let manager = ApplicationManager()
    XCTAssertNil(manager.runningApplication(processIdentifier: -1))
    XCTAssertTrue(manager.runningApplications(bundleIdentifier: " ").isEmpty)
    XCTAssertNil(manager.installedApplicationURL(bundleIdentifier: " "))
    XCTAssertEqual(
      manager.openApplication(bundleIdentifier: " "), .failed(.invalidBundleIdentifier))
    XCTAssertEqual(
      manager.activateApplication(processIdentifier: -1), .failed(.invalidProcessIdentifier))
    XCTAssertEqual(
      manager.terminateApplication(processIdentifier: -1), .failed(.invalidProcessIdentifier))
    let current = manager.currentApplication()
    if let current {
      XCTAssertEqual(current.processIdentifier, ProcessInfo.processInfo.processIdentifier)
    }
  }

  @MainActor
  func testNamedInstallationRejectsNULInsteadOfSelectingAnotherPath() throws {
    let files = FileManager.default
    let parent = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: parent) }
    let first = parent.appendingPathComponent("First", isDirectory: true)
    let next = parent.appendingPathComponent("Next", isDirectory: true)
    let name = "Owned.app"
    for directory in [first, next] {
      try files.createDirectory(
        at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    let manager = ApplicationManager()
    let malformedDirectory = first.path + "\0"
    XCTAssertNil(
      manager.installedApplicationURL(named: name + "\0", searchDirectories: [first.path]))
    XCTAssertNil(
      manager.installedApplicationURL(named: name, searchDirectories: [malformedDirectory]))

    let found = manager.installedApplicationURL(
      named: name, searchDirectories: [malformedDirectory, next.path])
    XCTAssertEqual(found?.standardizedFileURL.path, next.appendingPathComponent(name).path)
  }
}
