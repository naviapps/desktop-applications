import AppKit
import DesktopApplications
import Foundation

extension ApplicationManager {

  /// Validates and opens an installed application matching the bundle identifier.
  /// Rejects a standard macOS bundle whose readable identifier differs from the request.
  public func openApplication(bundleIdentifier: String) -> ApplicationRequestResult<
    ApplicationLaunchError
  > {
    switch validatedInstalledApplicationURL(bundleIdentifier: bundleIdentifier) {
    case .success(let appURL):
      return requestOpening(appURL)
    case .failure(let error):
      return .failed(error)
    }
  }

  /// Validates and opens the application bundle at the file URL.
  public func openApplication(at url: URL) -> ApplicationRequestResult<ApplicationLaunchError> {
    if let validationError = applicationBundleURLValidationError(for: url) {
      return .failed(validationError)
    }
    return requestOpening(url)
  }

  /// Validates and opens an installed application asynchronously.
  /// Throws `CancellationError` if cancellation wins completion. A dispatched
  /// OS request may still launch the application after the wait is cancelled.
  public func openApplication(
    bundleIdentifier: String,
    configuration: NSWorkspace.OpenConfiguration
  ) async throws(CancellationError) -> ApplicationRequestResult<ApplicationLaunchError> {
    if Task.isCancelled { throw CancellationError() }
    let resolution = validatedInstalledApplicationURL(bundleIdentifier: bundleIdentifier)
    if Task.isCancelled { throw CancellationError() }
    switch resolution {
    case .success(let appURL):
      return try await requestConfiguredApplicationOpening(
        at: appURL,
        configuration: configuration
      )
    case .failure(let error):
      return .failed(error)
    }
  }

  /// Validates and opens the application bundle asynchronously.
  /// Throws `CancellationError` if cancellation wins completion. Cancellation
  /// ends the wait without withdrawing a dispatched OS request.
  public func openApplication(
    at url: URL,
    configuration: NSWorkspace.OpenConfiguration
  ) async throws(CancellationError) -> ApplicationRequestResult<ApplicationLaunchError> {
    if Task.isCancelled { throw CancellationError() }
    let validationError = applicationBundleURLValidationError(for: url)
    if Task.isCancelled { throw CancellationError() }
    if let validationError {
      return .failed(validationError)
    }
    return try await requestConfiguredApplicationOpening(at: url, configuration: configuration)
  }

  private func applicationBundleURLValidationError(for url: URL)
    -> ApplicationLaunchError?
  {
    if case .failure(let error) = validatedExecutableURL(for: url) { return error }
    return nil
  }

  private func validatedExecutableURL(for url: URL) -> Result<URL, ApplicationLaunchError> {
    guard url.isFileURL else { return .failure(.invalidApplicationBundleURL) }
    guard url.pathExtension.lowercased() == "app" else {
      return .failure(.invalidApplicationBundleURL)
    }
    guard dependencies.fileExists(url) else {
      return .failure(.applicationBundleNotFound)
    }
    guard dependencies.directoryExists(url) else { return .failure(.invalidApplicationBundleURL) }
    guard
      let bundleInfo = dependencies.applicationBundleInfo(url),
      bundleInfo.packageType == "APPL",
      let executableURL = bundleInfo.executableURL,
      dependencies.executableFileExists(executableURL)
    else {
      return .failure(.invalidApplicationBundleURL)
    }
    return .success(executableURL)
  }

  private func validatedInstalledApplicationURL(
    bundleIdentifier: String
  ) -> Result<URL, ApplicationLaunchError> {
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else {
      return .failure(.invalidBundleIdentifier)
    }
    guard
      let appURL = dependencies.installedApplicationURL(workspace, bundleIdentifier)
    else {
      return .failure(.installedApplicationNotFound)
    }
    let executableURL: URL
    switch validatedExecutableURL(for: appURL) {
    case .success(let url): executableURL = url
    case .failure(let error): return .failure(error)
    }
    if let identifier = installedLaunchIdentifier(at: appURL, executableURL: executableURL),
      !Self.matchesBundleIdentifier(identifier, bundleIdentifier)
    {
      return .failure(.installedApplicationNotFound)
    }
    return .success(appURL)
  }

  private func installedLaunchIdentifier(at appURL: URL, executableURL: URL) -> String? {
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
    guard
      executableURL.deletingLastPathComponent().standardizedFileURL.path
        == executableDirectory.standardizedFileURL.path
    else { return nil }

    let plist = ApplicationBundleMetadata.infoPlistURL(
      for: appURL, fileExists: dependencies.fileExists)
    return ApplicationBundleIdentifierInput.identifier(inInfoPlistAt: plist)
  }

  private static func matchesBundleIdentifier(_ actual: String, _ expected: String) -> Bool {
    // Apple's case-insensitive bundle identifier alphabet uses ASCII letters.
    func lowercaseASCII(_ byte: UInt8) -> UInt8 {
      (65...90).contains(byte) ? byte + 32 : byte
    }
    return actual.utf8.elementsEqual(expected.utf8) { lowercaseASCII($0) == lowercaseASCII($1) }
  }

  private func requestOpening(_ url: URL) -> ApplicationRequestResult<ApplicationLaunchError> {
    Self.requestResult(
      isAccepted: dependencies.requestOpening(workspace, url),
      rejectedError: .requestRejected
    )
  }

  private func requestConfiguredApplicationOpening(
    at url: URL,
    configuration: NSWorkspace.OpenConfiguration
  ) async throws(CancellationError)
    -> ApplicationRequestResult<ApplicationLaunchError>
  {
    if Task.isCancelled { throw CancellationError() }
    let request = ApplicationOpeningRequest()
    let isAccepted = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard request.begin(continuation) else { return }
        dependencies.requestConfiguredApplicationOpening(workspace, url, configuration) {
          request.finish($0)
        }
      }
    } onCancel: {
      request.finish(nil)
    }
    guard let isAccepted else { throw CancellationError() }
    return Self.requestResult(
      isAccepted: isAccepted,
      rejectedError: .requestRejected
    )
  }
}
