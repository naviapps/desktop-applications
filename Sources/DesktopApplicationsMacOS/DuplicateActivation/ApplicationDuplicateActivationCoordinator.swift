import AppKit
import Foundation

/// Coordinates activation requests from duplicate processes using distributed notifications.
///
/// The host app provides its bundle identifier, and may override the distributed
/// notification name when coordinating with an existing app-specific convention.
/// Keep the coordinator alive for as long as duplicate-process activation requests should be
/// observed.
/// This coordinator does not acquire a process ownership lock; the host app decides whether a
/// duplicate process exits after posting the activation request.
@MainActor
public final class ApplicationDuplicateActivationCoordinator {
  /// Describes why duplicate-process activation request coordination could not be configured.
  public enum ConfigurationError: Error, Sendable, Equatable, Hashable {
    /// The bundle identifier is blank after trimming whitespace.
    case invalidBundleIdentifier
    /// The distributed notification name is blank after trimming whitespace.
    case invalidNotificationName
  }

  /// Represents a duplicate-process activation request coordination result.
  public enum CoordinationResult: Sendable, Equatable, Hashable {
    /// No other currently running process was found, and activation requests are being observed.
    case unique
    /// Another running process was found, and an activation request was posted.
    case duplicate
  }

  private let bundleIdentifier: String
  private let notificationName: Notification.Name
  private let dependencies: ApplicationDuplicateActivationCoordinatorDependencies
  private var activationObserverToken: ApplicationDuplicateActivationObserverToken?

  /// Creates a coordinator with a default notification name derived from the bundle identifier.
  ///
  /// - Throws: `ConfigurationError.invalidBundleIdentifier` when the bundle identifier is blank.
  public convenience init(bundleIdentifier: String) throws {
    let bundleIdentifier = try Self.trimmedBundleIdentifier(bundleIdentifier)
    try self.init(
      bundleIdentifier: bundleIdentifier,
      notificationName: Self.defaultNotificationName(
        trimmedBundleIdentifier: bundleIdentifier
      )
    )
  }

  /// Creates a coordinator with live distributed notification dependencies.
  ///
  /// - Throws: `ConfigurationError.invalidBundleIdentifier` when the bundle identifier is blank,
  ///   or `ConfigurationError.invalidNotificationName` when the notification name is blank.
  public convenience init(
    bundleIdentifier: String,
    notificationName: Notification.Name
  ) throws {
    try self.init(
      bundleIdentifier: bundleIdentifier,
      notificationName: notificationName,
      dependencies: .live()
    )
  }

  init(
    bundleIdentifier: String,
    notificationName: Notification.Name,
    dependencies: ApplicationDuplicateActivationCoordinatorDependencies
  ) throws {
    self.bundleIdentifier = try Self.trimmedBundleIdentifier(bundleIdentifier)
    self.notificationName = try Self.validatedNotificationName(notificationName)
    self.dependencies = dependencies
  }

  /// Coordinates duplicate-process activation requests.
  ///
  /// - Returns: `.unique` when no other running process is found, or `.duplicate`
  ///   after posting an activation request to a duplicate process.
  /// Keep this coordinator alive after `.unique`; `stop()` or deinitialization removes the observer.
  public func coordinate(
    onDuplicateActivationRequest: @escaping @MainActor @Sendable () -> Void
  ) -> CoordinationResult {
    stop()

    if !runningDuplicateProcessIdentifiers().isEmpty {
      postActivationRequestToDuplicateProcess()
      return .duplicate
    }

    activationObserverToken = observeActivationRequests(
      onDuplicateActivationRequest: onDuplicateActivationRequest
    )

    return .unique
  }

  /// Coordinates duplicate-process activation requests and activates this process when requested.
  ///
  /// - Returns: `.unique` when no other running process is found, or `.duplicate`
  ///   after posting an activation request to a duplicate process.
  /// Keep this coordinator alive after `.unique`; `stop()` or deinitialization removes the observer.
  public func coordinateActivatingCurrentApplication(
    options: NSApplication.ActivationOptions = []
  ) -> CoordinationResult {
    let activateCurrentApplication = dependencies.activateCurrentApplication
    return coordinate {
      _ = activateCurrentApplication(options)
    }
  }

  /// Stops observing activation requests from future duplicate processes.
  public func stop() {
    activationObserverToken?.cancel()
    activationObserverToken = nil
  }

  private static func defaultNotificationName(trimmedBundleIdentifier bundleIdentifier: String)
    -> Notification.Name
  {
    Notification.Name("\(bundleIdentifier).duplicate-process-activation-request.activate")
  }

  private static func trimmedBundleIdentifier(_ bundleIdentifier: String) throws -> String {
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else {
      throw ConfigurationError.invalidBundleIdentifier
    }
    return bundleIdentifier
  }

  private static func validatedNotificationName(_ notificationName: Notification.Name) throws
    -> Notification.Name
  {
    let trimmedName = notificationName.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw ConfigurationError.invalidNotificationName
    }
    return Notification.Name(trimmedName)
  }

  private func runningDuplicateProcessIdentifiers() -> [pid_t] {
    let currentProcessIdentifier = dependencies.currentProcessIdentifier()
    let processIdentifiers =
      dependencies
      .runningProcessIdentifiers(bundleIdentifier)
      .filter { $0 > 0 && $0 != currentProcessIdentifier }
    return processIdentifiers
  }

  private func postActivationRequestToDuplicateProcess() {
    dependencies.activationRequestTransport.postActivationRequest(
      name: notificationName,
      bundleIdentifier: bundleIdentifier
    )
  }

  private func observeActivationRequests(
    onDuplicateActivationRequest: @escaping @MainActor @Sendable () -> Void
  ) -> ApplicationDuplicateActivationObserverToken {
    let activationRequestTransport = dependencies.activationRequestTransport
    let activationRequestObserver = activationRequestTransport.observeActivationRequests(
      name: notificationName,
      bundleIdentifier: bundleIdentifier,
      handler: onDuplicateActivationRequest
    )
    return ApplicationDuplicateActivationObserverToken(
      activationRequestTransport: activationRequestTransport,
      observer: activationRequestObserver
    )
  }
}

private final class ApplicationDuplicateActivationObserverToken {
  private let activationRequestTransport: ApplicationDuplicateActivationRequestTransport
  private var observer: NSObjectProtocol?

  init(
    activationRequestTransport: ApplicationDuplicateActivationRequestTransport,
    observer: NSObjectProtocol
  ) {
    self.activationRequestTransport = activationRequestTransport
    self.observer = observer
  }

  func cancel() {
    guard let observer else { return }
    activationRequestTransport.removeActivationRequestObserver(observer)
    self.observer = nil
  }

  deinit {
    cancel()
  }
}
