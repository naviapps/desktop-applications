import AppKit
import DesktopApplications
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerOpeningValidationTests: XCTestCase {

  func testValidatesBundleIdentifierInputs() async throws {
    try await assertOpeningApplicationValidationError(
      bundleIdentifier: Self.blankBundleIdentifier,
      .invalidBundleIdentifier
    )
  }

  func testValidatesApplicationBundleURLInputs() async throws {
    for scenario in InvalidApplicationBundleURLScenario.allCases {
      let url = try scenario.makeURL()
      defer { scenario.removeTemporaryItemIfNeeded(at: url) }

      try await assertOpeningApplicationValidationError(
        at: url,
        scenario.expectedError,
        message: scenario.name
      )
    }
  }

  func testValidatesResolvedApplicationBundleURLInputs() async throws {
    for scenario in InvalidApplicationBundleURLScenario.allCases {
      let url = try scenario.makeURL()
      defer { scenario.removeTemporaryItemIfNeeded(at: url) }

      try await assertOpeningResolvedApplicationValidationError(
        url,
        scenario.expectedError,
        bundleIdentifier: Self.bundleIdentifier,
        message: scenario.name
      )
    }
  }

  private static let blankBundleIdentifier = "   "
  private static let bundleIdentifier = "com.example.app"

}

private enum InvalidApplicationBundleURLScenario: CaseIterable {
  case remoteURL
  case missingLowercaseApp
  case missingUppercaseApp
  case applicationFile
  case nonApplicationDirectory
  case emptyApplicationDirectory
  case nonApplicationBundle
  case missingExecutableBundle
  case directoryExecutableBundle
  case nonExecutableBundle

  var name: String {
    switch self {
    case .remoteURL:
      "remote URL"
    case .missingLowercaseApp:
      "missing .app"
    case .missingUppercaseApp:
      "missing .APP"
    case .applicationFile:
      ".app file"
    case .nonApplicationDirectory:
      "non-.app directory"
    case .emptyApplicationDirectory:
      "empty .app directory"
    case .nonApplicationBundle:
      "non-APPL bundle"
    case .missingExecutableBundle:
      "bundle without executable"
    case .directoryExecutableBundle:
      "bundle with directory executable"
    case .nonExecutableBundle:
      "bundle with non-executable file"
    }
  }

  var expectedError: ApplicationLaunchError {
    switch self {
    case .missingLowercaseApp, .missingUppercaseApp:
      .applicationBundleNotFound
    case .remoteURL,
      .applicationFile,
      .nonApplicationDirectory,
      .emptyApplicationDirectory,
      .nonApplicationBundle,
      .missingExecutableBundle,
      .directoryExecutableBundle,
      .nonExecutableBundle:
      .invalidApplicationBundleURL
    }
  }

  func makeURL() throws -> URL {
    switch self {
    case .remoteURL:
      return try XCTUnwrap(URL(string: "https://example.com"))
    case .missingLowercaseApp:
      return missingFileURL(pathExtension: "app")
    case .missingUppercaseApp:
      return missingFileURL(pathExtension: "APP")
    case .applicationFile:
      return try temporaryFileURL(pathExtension: "app")
    case .nonApplicationDirectory:
      let url = temporaryDirectoryURL(prefix: "not-an-app")
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      return url
    case .emptyApplicationDirectory:
      let url = temporaryDirectoryURL(prefix: "empty", pathExtension: "app")
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      return url
    case .nonApplicationBundle:
      return try temporaryApplicationBundleURL(packageType: "BNDL")
    case .missingExecutableBundle:
      return try temporaryApplicationBundleURL(executableKind: .missing)
    case .directoryExecutableBundle:
      return try temporaryApplicationBundleURL(executableKind: .directory)
    case .nonExecutableBundle:
      return try temporaryApplicationBundleURL(executableKind: .nonExecutableFile)
    }
  }

  func removeTemporaryItemIfNeeded(at url: URL) {
    guard shouldRemoveTemporaryItem else { return }
    removeTemporaryItem(at: url)
  }

  private var shouldRemoveTemporaryItem: Bool {
    switch self {
    case .remoteURL, .missingLowercaseApp, .missingUppercaseApp:
      false
    case .applicationFile,
      .nonApplicationDirectory,
      .emptyApplicationDirectory,
      .nonApplicationBundle,
      .missingExecutableBundle,
      .directoryExecutableBundle,
      .nonExecutableBundle:
      true
    }
  }

}
