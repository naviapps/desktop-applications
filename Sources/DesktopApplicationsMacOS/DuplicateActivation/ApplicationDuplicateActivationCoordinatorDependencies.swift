import AppKit
import Foundation

protocol ApplicationDuplicateActivationRequestTransport {
  func postActivationRequest(name: Notification.Name, bundleIdentifier: String)
  func observeActivationRequests(
    name: Notification.Name,
    bundleIdentifier: String,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> NSObjectProtocol
  func removeActivationRequestObserver(_ observer: NSObjectProtocol)
}

protocol ApplicationDuplicateActivationNotificationCenter {
  func post(name: Notification.Name, object: String?)
  func addObserver(
    forName name: Notification.Name?,
    object: String?,
    queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol
  func removeObserver(_ observer: NSObjectProtocol)
}

struct LiveDuplicateActivationNotificationCenter: ApplicationDuplicateActivationNotificationCenter {
  private let notificationCenter: DistributedNotificationCenter

  init(notificationCenter: DistributedNotificationCenter = .default()) {
    self.notificationCenter = notificationCenter
  }

  func post(name: Notification.Name, object: String?) {
    notificationCenter.post(name: name, object: object)
  }

  func addObserver(
    forName name: Notification.Name?,
    object: String?,
    queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol {
    notificationCenter.addObserver(
      forName: name,
      object: object,
      queue: queue,
      using: block
    )
  }

  func removeObserver(_ observer: NSObjectProtocol) {
    notificationCenter.removeObserver(observer)
  }
}

struct ApplicationDuplicateActivationCoordinatorDependencies {
  let activateCurrentApplication:
    @MainActor @Sendable (_ options: NSApplication.ActivationOptions) -> Bool
  let currentProcessIdentifier: @MainActor @Sendable () -> pid_t
  let runningProcessIdentifiers: @MainActor @Sendable (_ bundleIdentifier: String) -> [pid_t]
  let activationRequestTransport: ApplicationDuplicateActivationRequestTransport

  init(
    activateCurrentApplication:
      @escaping @MainActor @Sendable (
        _ options: NSApplication.ActivationOptions
      ) -> Bool = { _ in false },
    currentProcessIdentifier: @escaping @MainActor @Sendable () -> pid_t = { 0 },
    runningProcessIdentifiers:
      @escaping @MainActor @Sendable (
        _ bundleIdentifier: String
      ) -> [pid_t] = { _ in [] },
    activationRequestTransport: ApplicationDuplicateActivationRequestTransport
  ) {
    self.activateCurrentApplication = activateCurrentApplication
    self.currentProcessIdentifier = currentProcessIdentifier
    self.runningProcessIdentifiers = runningProcessIdentifiers
    self.activationRequestTransport = activationRequestTransport
  }

  static func live() -> Self {
    Self(
      activateCurrentApplication: { options in
        NSRunningApplication.current.activate(options: options)
      },
      currentProcessIdentifier: { ProcessInfo.processInfo.processIdentifier },
      runningProcessIdentifiers: { bundleIdentifier in
        NSRunningApplication
          .runningApplications(withBundleIdentifier: bundleIdentifier)
          .map(\.processIdentifier)
      },
      activationRequestTransport: DistributedNotificationActivationRequestTransport()
    )
  }
}

struct DistributedNotificationActivationRequestTransport:
  ApplicationDuplicateActivationRequestTransport
{
  private let notificationCenter: ApplicationDuplicateActivationNotificationCenter

  init(
    notificationCenter: ApplicationDuplicateActivationNotificationCenter =
      LiveDuplicateActivationNotificationCenter()
  ) {
    self.notificationCenter = notificationCenter
  }

  func postActivationRequest(name: Notification.Name, bundleIdentifier: String) {
    notificationCenter.post(name: name, object: bundleIdentifier)
  }

  func observeActivationRequests(
    name: Notification.Name,
    bundleIdentifier: String,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> NSObjectProtocol {
    notificationCenter
      .addObserver(forName: name, object: bundleIdentifier, queue: .main) { _ in
        Task { @MainActor in
          handler()
        }
      }
  }

  func removeActivationRequestObserver(_ observer: NSObjectProtocol) {
    notificationCenter.removeObserver(observer)
  }
}
