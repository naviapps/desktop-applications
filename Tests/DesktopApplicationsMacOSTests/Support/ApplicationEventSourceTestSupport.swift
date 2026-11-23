import AppKit
import DesktopApplications
import Synchronization
import XCTest

@testable import DesktopApplicationsMacOS

/// Models live notifications by default; tests may explicitly opt in to buffered history.
@MainActor
final class TestApplicationEventSource: ApplicationEventSource {
  private struct EventSubscription {
    let id: Int
    let lifecycles: Set<ApplicationEvent.Lifecycle>
    let continuation: AsyncStream<ApplicationEvent>.Continuation
  }

  private var eventSubscriptions: [EventSubscription] = []
  private var nextEventSubscriptionID = 0
  private var replayedEvents: [ApplicationEvent] = []
  private let replaysPastEvents: Bool

  init(replaysPastEvents: Bool = false) {
    self.replaysPastEvents = replaysPastEvents
  }

  func eventStream(lifecycles: Set<ApplicationEvent.Lifecycle>) -> AsyncStream<
    ApplicationEvent
  > {
    return AsyncStream { continuation in
      guard !lifecycles.isEmpty else {
        continuation.finish()
        return
      }
      for event in replayedEvents where lifecycles.contains(event.lifecycle) {
        continuation.yield(event)
      }
      nextEventSubscriptionID += 1
      let id = nextEventSubscriptionID
      eventSubscriptions.append(
        EventSubscription(id: id, lifecycles: lifecycles, continuation: continuation)
      )
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in
          self?.removeEventSubscription(id: id)
        }
      }
    }
  }

  func emit(_ lifecycleCase: ApplicationManagerLifecycleCase, snapshot: ApplicationSnapshot?) {
    guard let snapshot else { return }
    let event = ApplicationEvent(lifecycle: lifecycleCase.lifecycle, application: snapshot)
    if replaysPastEvents { replayedEvents.append(event) }
    for subscription in eventSubscriptions where subscription.lifecycles.contains(event.lifecycle) {
      subscription.continuation.yield(event)
    }
  }

  private func removeEventSubscription(id: Int) {
    eventSubscriptions.removeAll { $0.id == id }
  }
}

final class TestApplicationEventNotificationCenter: NotificationCenter, @unchecked Sendable {
  private let observerTokens = Mutex(Set<ObjectIdentifier>())
  private let observerRemoved: @Sendable () -> Void

  init(observerRemoved: @escaping @Sendable () -> Void = {}) {
    self.observerRemoved = observerRemoved
    super.init()
  }

  var observerCount: Int {
    observerTokens.withLock { $0.count }
  }

  override func addObserver(
    forName name: Notification.Name?,
    object: Any?,
    queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol {
    let token = super.addObserver(forName: name, object: object, queue: queue, using: block)
    _ = observerTokens.withLock { $0.insert(ObjectIdentifier(token as AnyObject)) }
    return token
  }

  override func removeObserver(_ observer: Any) {
    super.removeObserver(observer)
    let removed = observerTokens.withLock { $0.remove(ObjectIdentifier(observer as AnyObject)) }
    if removed != nil { observerRemoved() }
  }
}

@MainActor
func applicationRuntime(eventSource: TestApplicationEventSource) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      eventSource: { _ in eventSource }
    )
  )
}

@MainActor
func applicationRuntime(notificationCenter: NotificationCenter) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      eventSource: { _ in WorkspaceApplicationEventSource(notificationCenter: notificationCenter) }
    )
  )
}

func applicationRuntimeEventSnapshot(
  processIdentifier: pid_t = 123,
  bundleIdentifier: String = "com.example.event",
  displayName: String = "Example Event App",
  isTerminated: Bool = false
) -> ApplicationSnapshot {
  ApplicationSnapshot(
    processIdentifier: processIdentifier,
    bundleIdentifier: bundleIdentifier,
    displayName: displayName,
    isTerminated: isTerminated
  )
}

func assertApplicationEventSnapshot(
  _ snapshot: ApplicationSnapshot?,
  matches expected: ApplicationSnapshot,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(snapshot, expected, file: file, line: line)
}

@MainActor
func applicationRuntimeEventWaitTask(
  runtime: ApplicationManager,
  lifecycle: ApplicationEvent.Lifecycle,
  bundleIdentifier: String,
  timeout: Duration
) -> Task<ApplicationEvent?, Never> {
  Task {
    await runtime.waitForApplicationEvent(
      lifecycle,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )
  }
}

enum ApplicationManagerLifecycleCase: CaseIterable {
  case launch
  case termination
  case activation
  case deactivation

  var label: String {
    switch self {
    case .launch:
      "launch"
    case .termination:
      "termination"
    case .activation:
      "activation"
    case .deactivation:
      "deactivation"
    }
  }

  var lifecycle: ApplicationEvent.Lifecycle {
    switch self {
    case .launch:
      .launched
    case .termination:
      .terminated
    case .activation:
      .activated
    case .deactivation:
      .deactivated
    }
  }

  var notificationName: Notification.Name {
    switch self {
    case .launch:
      NSWorkspace.didLaunchApplicationNotification
    case .termination:
      NSWorkspace.didTerminateApplicationNotification
    case .activation:
      NSWorkspace.didActivateApplicationNotification
    case .deactivation:
      NSWorkspace.didDeactivateApplicationNotification
    }
  }

  var differentLifecycleCase: ApplicationManagerLifecycleCase {
    switch self {
    case .launch:
      .activation
    case .termination:
      .launch
    case .activation:
      .launch
    case .deactivation:
      .launch
    }
  }

  @MainActor
  func applicationSnapshots(from runtime: ApplicationManager) -> AsyncStream<
    ApplicationSnapshot
  > {
    switch self {
    case .launch:
      runtime.launchEvents()
    case .termination:
      runtime.terminationEvents()
    case .activation:
      runtime.activationEvents()
    case .deactivation:
      runtime.deactivationEvents()
    }
  }

  @MainActor
  func waitForSnapshot(
    from runtime: ApplicationManager,
    bundleIdentifier: String,
    timeout: Duration
  ) async -> ApplicationSnapshot? {
    await waitForSnapshotTask(
      from: runtime,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    ).value
  }

  @MainActor
  func waitForSnapshotTask(
    from runtime: ApplicationManager,
    bundleIdentifier: String,
    timeout: Duration
  ) -> Task<ApplicationSnapshot?, Never> {
    Task {
      await self.waitForSnapshotValue(
        from: runtime,
        bundleIdentifier: bundleIdentifier,
        timeout: timeout
      )
    }
  }

  @MainActor
  private func waitForSnapshotValue(
    from runtime: ApplicationManager,
    bundleIdentifier: String,
    timeout: Duration
  ) async -> ApplicationSnapshot? {
    switch self {
    case .launch:
      await runtime.waitForApplicationLaunch(
        bundleIdentifier: bundleIdentifier,
        timeout: timeout
      )
    case .termination:
      await runtime.waitForApplicationTermination(
        bundleIdentifier: bundleIdentifier,
        timeout: timeout
      )
    case .activation:
      await runtime.waitForApplicationActivation(
        bundleIdentifier: bundleIdentifier,
        timeout: timeout
      )
    case .deactivation:
      await runtime.waitForApplicationDeactivation(
        bundleIdentifier: bundleIdentifier,
        timeout: timeout
      )
    }
  }
}
