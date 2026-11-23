import AppKit
import Darwin
import DesktopApplications
import Foundation

extension ApplicationManager {
  /// Conventional macOS application search locations; callers may supply others.
  public nonisolated static let defaultSearchDirectories = [
    "/Applications", "/Applications/Utilities", "/System/Applications",
    "/System/Applications/Utilities", "/System/Library/CoreServices", "~/Applications",
  ]
  /// Returns native application snapshots; the host selects its activation policy.
  public func runningApplications(activationPolicy: NSApplication.ActivationPolicy? = nil)
    -> [ApplicationSnapshot]
  {
    dependencies.allRunningApplications(workspace)
      .filter { activationPolicy == nil || $0.activationPolicy == activationPolicy }
      .compactMap { Self.snapshot(for: $0) }
  }

  /// Returns all registered installations for an application identifier.
  public func installedApplicationURLs(bundleIdentifier: String) -> [URL] {
    guard let value = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier) else {
      return []
    }
    return workspace.urlsForApplications(withBundleIdentifier: value)
  }

  /// Resolves an explicit app name within caller-selected application directories.
  /// Names containing NUL return nil. Search directories containing NUL are skipped.
  public func installedApplicationURL(
    named name: String, searchDirectories: [String] = defaultSearchDirectories
  ) -> URL? {
    ApplicationBundleResolver(searchDirectories: searchDirectories).urlForApplication(named: name)
  }

  /// Returns a snapshot for the current application, if it is available.
  public func currentApplication() -> ApplicationSnapshot? {
    dependencies.currentApplication().flatMap(Self.snapshot)
  }

  /// Returns a snapshot for a running process identifier.
  public func runningApplication(processIdentifier: pid_t) -> ApplicationSnapshot? {
    switch runningApplication(matchingProcessIdentifier: processIdentifier) {
    case .success(let application):
      return Self.snapshot(for: application)
    case .failure:
      return nil
    }
  }

  /// Returns running applications matching the bundle identifier.
  public func runningApplications(bundleIdentifier: String) -> [ApplicationSnapshot] {
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else {
      return []
    }
    return
      runningApplications(matchingBundleIdentifier: bundleIdentifier)
      .compactMap(Self.snapshot)
  }

  func runningDisplayName(bundleIdentifier: String) -> String? {
    guard let identifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else { return nil }
    for application in runningApplications(matchingBundleIdentifier: identifier) {
      if let name = ApplicationBundleDisplayName.usableName(application.displayName) { return name }
    }
    return nil
  }

  /// Returns the current frontmost application, if one is available.
  public func frontmostApplication() -> ApplicationSnapshot? {
    dependencies.frontmostApplication(workspace).flatMap(Self.snapshot)
  }

  /// Returns the installed application URL matching the bundle identifier.
  public func installedApplicationURL(bundleIdentifier: String) -> URL? {
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else {
      return nil
    }
    return dependencies.installedApplicationURL(workspace, bundleIdentifier)
  }
}
