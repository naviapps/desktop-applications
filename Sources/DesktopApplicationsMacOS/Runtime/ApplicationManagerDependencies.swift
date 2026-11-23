import AppKit
import Foundation

struct ApplicationBundleInfo: Sendable, Equatable {
  let packageType: String?
  let executableURL: URL?
}

struct ApplicationManagerDependencies {
  let allRunningApplications:
    @MainActor @Sendable (_ workspace: NSWorkspace) -> [NSRunningApplication]
  let currentApplication: @MainActor @Sendable () -> (any ApplicationManagerRunningApplication)?
  let runningApplication:
    @MainActor @Sendable (_ processIdentifier: pid_t) -> (
      any ApplicationManagerRunningApplication
    )?
  let runningApplications:
    @MainActor @Sendable (_ bundleIdentifier: String) -> [any ApplicationManagerRunningApplication]
  let frontmostApplication:
    @MainActor @Sendable (_ workspace: NSWorkspace) -> (any ApplicationManagerRunningApplication)?
  let installedApplicationURL:
    @MainActor @Sendable (_ workspace: NSWorkspace, _ bundleIdentifier: String) -> URL?
  let requestOpening: @MainActor @Sendable (_ workspace: NSWorkspace, _ url: URL) -> Bool
  let requestConfiguredApplicationOpening:
    @MainActor @Sendable (
      _ workspace: NSWorkspace,
      _ url: URL,
      _ configuration: NSWorkspace.OpenConfiguration,
      _ completion: @escaping @Sendable (Bool) -> Void
    ) -> Void
  let fileExists: @MainActor @Sendable (_ url: URL) -> Bool
  let directoryExists: @MainActor @Sendable (_ url: URL) -> Bool
  let executableFileExists: @MainActor @Sendable (_ url: URL) -> Bool
  let applicationBundleInfo: @MainActor @Sendable (_ url: URL) -> ApplicationBundleInfo?
  let eventSource: @MainActor @Sendable (_ workspace: NSWorkspace) -> any ApplicationEventSource

  init(
    allRunningApplications: @escaping @MainActor @Sendable (NSWorkspace) -> [NSRunningApplication] =
      { _ in [] },
    currentApplication:
      @escaping @MainActor @Sendable () -> (
        any ApplicationManagerRunningApplication
      )? = { nil },
    runningApplication:
      @escaping @MainActor @Sendable (_ processIdentifier: pid_t) -> (
        any ApplicationManagerRunningApplication
      )? = { _ in nil },
    runningApplications:
      @escaping @MainActor @Sendable (_ bundleIdentifier: String) ->
      [any ApplicationManagerRunningApplication] = { _ in [] },
    frontmostApplication:
      @escaping @MainActor @Sendable (_ workspace: NSWorkspace) -> (
        any ApplicationManagerRunningApplication
      )? = { _ in nil },
    installedApplicationURL:
      @escaping @MainActor @Sendable (
        _ workspace: NSWorkspace,
        _ bundleIdentifier: String
      ) -> URL? = { _, _ in nil },
    requestOpening:
      @escaping @MainActor @Sendable (
        _ workspace: NSWorkspace,
        _ url: URL
      ) -> Bool = { _, _ in false },
    requestConfiguredApplicationOpening:
      @escaping @MainActor @Sendable (
        _ workspace: NSWorkspace,
        _ url: URL,
        _ configuration: NSWorkspace.OpenConfiguration,
        _ completion: @escaping @Sendable (Bool) -> Void
      ) -> Void = { _, _, _, completion in completion(false) },
    fileExists:
      @escaping @MainActor @Sendable (_ url: URL) -> Bool = Self.defaultFileExists,
    directoryExists:
      @escaping @MainActor @Sendable (_ url: URL) -> Bool = Self.defaultDirectoryExists,
    executableFileExists:
      @escaping @MainActor @Sendable (_ url: URL) -> Bool = Self.defaultExecutableFileExists,
    applicationBundleInfo:
      @escaping @MainActor @Sendable (_ url: URL) -> ApplicationBundleInfo? =
      Self.defaultApplicationBundleInfo,
    eventSource:
      @escaping @MainActor @Sendable (
        _ workspace: NSWorkspace
      ) -> any ApplicationEventSource = { _ in InertApplicationEventSource() }
  ) {
    self.allRunningApplications = allRunningApplications
    self.currentApplication = currentApplication
    self.runningApplication = runningApplication
    self.runningApplications = runningApplications
    self.frontmostApplication = frontmostApplication
    self.installedApplicationURL = installedApplicationURL
    self.requestOpening = requestOpening
    self.requestConfiguredApplicationOpening = requestConfiguredApplicationOpening
    self.fileExists = fileExists
    self.directoryExists = directoryExists
    self.executableFileExists = executableFileExists
    self.applicationBundleInfo = applicationBundleInfo
    self.eventSource = eventSource
  }

  static func live() -> Self {
    Self(
      allRunningApplications: { $0.runningApplications },
      currentApplication: {
        NSRunningApplication.current
      },
      runningApplication: { processIdentifier in
        NSRunningApplication(processIdentifier: processIdentifier)
      },
      runningApplications: { bundleIdentifier in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      },
      frontmostApplication: { workspace in
        workspace.frontmostApplication
      },
      installedApplicationURL: { workspace, bundleIdentifier in
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
      },
      requestOpening: { workspace, url in
        workspace.open(url)
      },
      requestConfiguredApplicationOpening: { workspace, url, configuration, completion in
        workspace.openApplication(at: url, configuration: configuration) { application, error in
          completion(application != nil && error == nil)
        }
      },
      eventSource: { workspace in
        WorkspaceApplicationEventSource(workspace: workspace)
      }
    )
  }

  private static func defaultFileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  private static func defaultDirectoryExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    return isDirectory.boolValue
  }

  private static func defaultExecutableFileExists(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    guard !isDirectory.boolValue else { return false }
    return FileManager.default.isExecutableFile(atPath: url.path)
  }

  private static func defaultApplicationBundleInfo(_ url: URL) -> ApplicationBundleInfo? {
    guard let bundle = Bundle(url: url) else { return nil }
    return ApplicationBundleInfo(
      packageType: bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
      executableURL: bundle.executableURL
    )
  }
}
