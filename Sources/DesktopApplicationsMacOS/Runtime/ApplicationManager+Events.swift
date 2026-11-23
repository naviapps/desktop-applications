import DesktopApplications
import Foundation

extension ApplicationManager {
  /// Returns an async stream of all application lifecycle events.
  public func events() -> AsyncStream<ApplicationEvent> {
    events(lifecycles: Set(ApplicationEvent.Lifecycle.allCases))
  }

  /// Subscribes synchronously to the requested application lifecycle events.
  ///
  /// Only the specified notifications are observed. Events received after
  /// subscription buffer until consumed; an empty set returns a finished stream.
  public func events(lifecycles: Set<ApplicationEvent.Lifecycle>) -> AsyncStream<ApplicationEvent> {
    eventSource.eventStream(lifecycles: lifecycles)
  }

  /// Returns an async stream of application launch events.
  public func launchEvents() -> AsyncStream<ApplicationSnapshot> {
    applicationSnapshots(lifecycle: .launched)
  }

  /// Returns an async stream of application termination events.
  public func terminationEvents() -> AsyncStream<ApplicationSnapshot> {
    applicationSnapshots(lifecycle: .terminated)
  }

  /// Returns an async stream of application activation events.
  public func activationEvents() -> AsyncStream<ApplicationSnapshot> {
    applicationSnapshots(lifecycle: .activated)
  }

  /// Returns an async stream of application deactivation events.
  public func deactivationEvents() -> AsyncStream<ApplicationSnapshot> {
    applicationSnapshots(lifecycle: .deactivated)
  }

  /// Waits for an application launch event matching the bundle identifier.
  public func waitForApplicationLaunch(
    bundleIdentifier: String,
    timeout: Duration? = nil
  ) async -> ApplicationSnapshot? {
    await waitForApplicationSnapshotEvent(
      .launched,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )
  }

  /// Waits for an application termination event matching the bundle identifier.
  public func waitForApplicationTermination(
    bundleIdentifier: String,
    timeout: Duration? = nil
  ) async -> ApplicationSnapshot? {
    await waitForApplicationSnapshotEvent(
      .terminated,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )
  }

  /// Waits for an application activation event matching the bundle identifier.
  public func waitForApplicationActivation(
    bundleIdentifier: String,
    timeout: Duration? = nil
  ) async -> ApplicationSnapshot? {
    await waitForApplicationSnapshotEvent(
      .activated,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )
  }

  /// Waits for an application deactivation event matching the bundle identifier.
  public func waitForApplicationDeactivation(
    bundleIdentifier: String,
    timeout: Duration? = nil
  ) async -> ApplicationSnapshot? {
    await waitForApplicationSnapshotEvent(
      .deactivated,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )
  }

  /// Waits for an application lifecycle event matching the lifecycle and bundle identifier.
  public func waitForApplicationEvent(
    _ lifecycle: ApplicationEvent.Lifecycle,
    bundleIdentifier: String,
    timeout: Duration? = nil
  ) async -> ApplicationEvent? {
    guard !Task.isCancelled, timeout.map({ $0 > .zero }) ?? true else { return nil }
    let deadline = timeout.map { ApplicationEventDeadline(timeout: $0) }
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier),
      !Task.isCancelled, deadline?.hasElapsed != true
    else {
      return nil
    }
    return await waitForMatchingApplicationEvent(
      lifecycle: lifecycle,
      bundleIdentifier: bundleIdentifier,
      deadline: deadline
    )
  }
}

extension ApplicationManager {
  fileprivate func waitForApplicationSnapshotEvent(
    _ lifecycle: ApplicationEvent.Lifecycle,
    bundleIdentifier: String,
    timeout: Duration?
  ) async -> ApplicationSnapshot? {
    await waitForApplicationEvent(
      lifecycle,
      bundleIdentifier: bundleIdentifier,
      timeout: timeout
    )?.application
  }

  fileprivate var eventSource: any ApplicationEventSource {
    dependencies.eventSource(workspace)
  }

  fileprivate func applicationSnapshots(
    lifecycle: ApplicationEvent.Lifecycle
  ) -> AsyncStream<ApplicationSnapshot> {
    // Register before returning so notifications buffer even before the forwarding task runs.
    let stream = events(lifecycles: [lifecycle])
    return AsyncStream<ApplicationSnapshot> { continuation in
      let task = Task {
        for await event in stream {
          continuation.yield(event.application)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  fileprivate func waitForMatchingApplicationEvent(
    lifecycle: ApplicationEvent.Lifecycle,
    bundleIdentifier: String,
    deadline: ApplicationEventDeadline?
  ) async -> ApplicationEvent? {
    let stream = events(lifecycles: [lifecycle])
    let identifier = ApplicationIdentifier(
      recordedKind: .bundle, value: bundleIdentifier.precomposedStringWithCanonicalMapping)
    return await withTaskGroup(of: ApplicationEvent?.self) { group in
      group.addTask {
        for await event in stream {
          guard !Task.isCancelled, deadline?.hasElapsed != true else {
            return nil
          }
          // Retain Swift String equality for legacy bundle-identifier waits.
          let recordedIdentifier = event.application.bundleIdentifier.map {
            ApplicationIdentifier(
              recordedKind: .bundle, value: $0.precomposedStringWithCanonicalMapping)
          }
          if event.matches(
            lifecycle: lifecycle, identifier: identifier, recordedIdentifier: recordedIdentifier)
          {
            return Task.isCancelled || deadline?.hasElapsed == true ? nil : event
          }
        }
        return nil
      }
      if let deadline {
        group.addTask {
          await deadline.sleepUntilElapsed()
          return nil
        }
      }
      let result = await group.next() ?? nil
      group.cancelAll()
      return Task.isCancelled ? nil : result
    }
  }
}

private struct ApplicationEventDeadline {
  let started = ContinuousClock.now
  let timeout: Duration

  var hasElapsed: Bool { started.duration(to: ContinuousClock.now) >= timeout }

  func sleepUntilElapsed() async {
    let clock = ContinuousClock()
    while true {
      let now = clock.now
      let remaining = timeout - started.duration(to: now)
      guard remaining > .zero else { return }
      // An unbounded deadline can overflow the Swift runtime's native timer.
      let delay = min(remaining, .seconds(86_400))
      do { try await clock.sleep(until: now.advanced(by: delay)) } catch { return }
    }
  }
}
