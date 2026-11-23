import AppKit
import DesktopApplications
import Foundation

@MainActor
protocol ApplicationEventSource {
  func eventStream(lifecycles: Set<ApplicationEvent.Lifecycle>) -> AsyncStream<
    ApplicationEvent
  >
}

struct InertApplicationEventSource: ApplicationEventSource {
  func eventStream(lifecycles _: Set<ApplicationEvent.Lifecycle>) -> AsyncStream<
    ApplicationEvent
  > {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

struct WorkspaceApplicationEventSource: ApplicationEventSource {
  private let notificationCenter: NotificationCenter

  init(workspace: NSWorkspace) {
    self.init(notificationCenter: workspace.notificationCenter)
  }

  init(notificationCenter: NotificationCenter) {
    self.notificationCenter = notificationCenter
  }

  func eventStream(lifecycles: Set<ApplicationEvent.Lifecycle>) -> AsyncStream<
    ApplicationEvent
  > {
    AsyncStream { continuation in
      guard !lifecycles.isEmpty else {
        continuation.finish()
        return
      }
      var tokens: [NSObjectProtocol] = []
      for lifecycle in lifecycles {
        let token = notificationCenter.addObserver(
          forName: Self.eventNotificationName(for: lifecycle),
          object: nil,
          queue: .main
        ) { notification in
          guard let snapshot = Self.applicationSnapshot(from: notification) else {
            return
          }
          continuation.yield(
            ApplicationEvent(
              lifecycle: lifecycle,
              application: snapshot
            )
          )
        }
        tokens.append(token)
      }
      let observerTokens = RuntimeEventObserverTokens(
        center: notificationCenter,
        tokens: tokens
      )
      continuation.onTermination = { _ in
        observerTokens.cancel()
      }
    }
  }

  nonisolated private static func applicationSnapshot(
    from notification: Notification
  ) -> ApplicationSnapshot? {
    guard
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
    else { return nil }
    return ApplicationSnapshot(runningApplication: app)
  }

  nonisolated private static func eventNotificationName(
    for lifecycle: ApplicationEvent.Lifecycle
  ) -> Notification.Name {
    switch lifecycle {
    case .launched:
      NSWorkspace.didLaunchApplicationNotification
    case .terminated:
      NSWorkspace.didTerminateApplicationNotification
    case .activated:
      NSWorkspace.didActivateApplicationNotification
    case .deactivated:
      NSWorkspace.didDeactivateApplicationNotification
    }
  }
}

private final class RuntimeEventObserverTokens: @unchecked Sendable {
  private let center: NotificationCenter
  private let lock = NSLock()
  private var tokens: [NSObjectProtocol]

  init(center: NotificationCenter, tokens: [NSObjectProtocol]) {
    self.center = center
    self.tokens = tokens
  }

  func cancel() {
    lock.lock()
    let tokens = self.tokens
    self.tokens = []
    lock.unlock()

    for token in tokens {
      center.removeObserver(token)
    }
  }

  deinit {
    cancel()
  }
}
