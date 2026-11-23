import AppKit
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class SynchronousOpeningRequestRecorder {
  private let workspace: NSWorkspace
  private let result: Bool
  private var requestedWorkspace: NSWorkspace?
  private var requestedURL: URL?

  init(
    workspace: NSWorkspace = NSWorkspace(),
    result: Bool = true
  ) {
    self.workspace = workspace
    self.result = result
  }

  func runtimeRequestingOpening() -> ApplicationManager {
    ApplicationManager(
      workspace: workspace,
      dependencies: ApplicationManagerDependencies(
        requestOpening: { workspace, url in
          self.requestedWorkspace = workspace
          self.requestedURL = url
          return self.result
        }
      )
    )
  }

  func assertRequestedOpening(
    _ expectedURL: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertIdentical(requestedWorkspace, workspace, file: file, line: line)
    XCTAssertEqual(requestedURL, expectedURL, file: file, line: line)
  }
}

@MainActor
final class ConfiguredOpeningRequestRecorder {
  private let workspace: NSWorkspace
  private let result: Bool
  private var requestedWorkspace: NSWorkspace?
  private var requestedURL: URL?
  private var requestedConfiguration: NSWorkspace.OpenConfiguration?

  init(
    workspace: NSWorkspace = NSWorkspace(),
    result: Bool = true
  ) {
    self.workspace = workspace
    self.result = result
  }

  func runtimeRequestingConfiguredApplicationOpening() -> ApplicationManager {
    ApplicationManager(
      workspace: workspace,
      dependencies: ApplicationManagerDependencies(
        requestConfiguredApplicationOpening: { workspace, url, configuration, completion in
          self.requestedWorkspace = workspace
          self.requestedURL = url
          self.requestedConfiguration = configuration
          completion(self.result)
        }
      )
    )
  }

  func assertRequestedOpening(
    _ expectedURL: URL,
    configuration expectedConfiguration: NSWorkspace.OpenConfiguration,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertIdentical(requestedWorkspace, workspace, file: file, line: line)
    XCTAssertEqual(requestedURL, expectedURL, file: file, line: line)
    XCTAssertIdentical(requestedConfiguration, expectedConfiguration, file: file, line: line)
  }
}

@MainActor
final class InstalledApplicationOpeningRequestRecorder {
  private let workspace: NSWorkspace
  private let applicationURL: URL?
  private let result: Bool
  private let unexpectedOpenMessage: String?
  private var lookedUpWorkspace: NSWorkspace?
  private var lookedUpBundleIdentifier: String?
  private var requestedWorkspace: NSWorkspace?
  private var requestedURL: URL?
  private var requestedConfiguration: NSWorkspace.OpenConfiguration?

  init(
    workspace: NSWorkspace = NSWorkspace(),
    applicationURL: URL?,
    result: Bool = true,
    unexpectedOpenMessage: String? = nil
  ) {
    self.workspace = workspace
    self.applicationURL = applicationURL
    self.result = result
    self.unexpectedOpenMessage = unexpectedOpenMessage
  }

  func runtimeRequestingResolvedApplicationOpening() -> ApplicationManager {
    ApplicationManager(
      workspace: workspace,
      dependencies: ApplicationManagerDependencies(
        installedApplicationURL: lookupInstalledApplicationURL,
        requestOpening: { workspace, url in
          self.recordOpeningRequest(workspace: workspace, url: url)
          return self.result
        }
      )
    )
  }

  func runtimeRequestingConfiguredResolvedApplicationOpening() -> ApplicationManager {
    ApplicationManager(
      workspace: workspace,
      dependencies: ApplicationManagerDependencies(
        installedApplicationURL: lookupInstalledApplicationURL,
        requestConfiguredApplicationOpening: { workspace, url, configuration, completion in
          self.recordOpeningRequest(workspace: workspace, url: url, configuration: configuration)
          completion(self.result)
        }
      )
    )
  }

  func assertLookedUp(
    _ expectedBundleIdentifier: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertIdentical(lookedUpWorkspace, workspace, file: file, line: line)
    XCTAssertEqual(lookedUpBundleIdentifier, expectedBundleIdentifier, file: file, line: line)
  }

  func assertRequestedOpening(
    _ expectedURL: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertIdentical(requestedWorkspace, workspace, file: file, line: line)
    XCTAssertEqual(requestedURL, expectedURL, file: file, line: line)
    XCTAssertNil(requestedConfiguration, file: file, line: line)
  }

  func assertRequestedOpening(
    _ expectedURL: URL,
    configuration expectedConfiguration: NSWorkspace.OpenConfiguration,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertIdentical(requestedWorkspace, workspace, file: file, line: line)
    XCTAssertEqual(requestedURL, expectedURL, file: file, line: line)
    XCTAssertIdentical(requestedConfiguration, expectedConfiguration, file: file, line: line)
  }

  private func lookupInstalledApplicationURL(
    workspace: NSWorkspace,
    bundleIdentifier: String
  ) -> URL? {
    lookedUpWorkspace = workspace
    lookedUpBundleIdentifier = bundleIdentifier
    return applicationURL
  }

  private func recordOpeningRequest(
    workspace: NSWorkspace,
    url: URL,
    configuration: NSWorkspace.OpenConfiguration? = nil
  ) {
    if let unexpectedOpenMessage {
      XCTFail(unexpectedOpenMessage)
    }
    requestedWorkspace = workspace
    requestedURL = url
    requestedConfiguration = configuration
  }
}
