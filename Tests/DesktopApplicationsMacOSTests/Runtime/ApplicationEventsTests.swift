import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationEventsTests: XCTestCase {
  func testApplicationEventsYieldsLifecycleAndApplication() async {
    let eventSource = TestApplicationEventSource()
    let application = applicationRuntimeEventSnapshot()
    let runtime = applicationRuntime(eventSource: eventSource)
    let stream = runtime.events()
    let task = Task { () -> [ApplicationEvent] in
      var values: [ApplicationEvent] = []
      for await value in stream {
        values.append(value)
        if values.count == ApplicationManagerLifecycleCase.allCases.count {
          return values
        }
      }
      return values
    }

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      eventSource.emit(lifecycleCase, snapshot: application)
    }

    let results = await task.value
    XCTAssertEqual(
      results.map(\.lifecycle), ApplicationManagerLifecycleCase.allCases.map(\.lifecycle))
    for result in results {
      assertApplicationEventSnapshot(
        result.application,
        matches: application
      )
    }
  }

  func testFilteredLifecycleEventsBufferOnlySelectedWorkspaceNotifications() async {
    let removed = expectation(description: "Selected workspace observers removed")
    removed.expectedFulfillmentCount = 2
    removed.assertForOverFulfill = true
    let center = TestApplicationEventNotificationCenter(observerRemoved: { removed.fulfill() })
    let runtime = applicationRuntime(notificationCenter: center)
    let userInfo = [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]

    center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil, userInfo: userInfo)
    let stream = runtime.events(lifecycles: [.launched, .terminated])
    XCTAssertEqual(center.observerCount, 2, "Only requested kinds should register observers")
    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      center.post(name: lifecycleCase.notificationName, object: nil, userInfo: userInfo)
    }

    let received = expectation(description: "Buffered launch and termination")
    received.expectedFulfillmentCount = 2
    received.assertForOverFulfill = true
    let finished = expectation(description: "Consumer stopped")
    var lifecycles: [ApplicationEvent.Lifecycle] = []
    let consumer = Task { @MainActor in
      defer { finished.fulfill() }
      for await event in stream {
        lifecycles.append(event.lifecycle)
        received.fulfill()
      }
    }

    await fulfillment(of: [received], timeout: 2)
    consumer.cancel()
    await fulfillment(of: [finished, removed], timeout: 2)
    XCTAssertEqual(lifecycles, [.launched, .terminated])
    XCTAssertEqual(center.observerCount, 0)
  }

  func testApplicationEventsIgnoreEventsWithoutApplicationSnapshot() async {
    let eventSource = TestApplicationEventSource()
    let application = applicationRuntimeEventSnapshot()
    let runtime = applicationRuntime(eventSource: eventSource)
    let task = firstValueTask(from: runtime.events())

    eventSource.emit(.launch, snapshot: nil)
    eventSource.emit(.launch, snapshot: application)

    let result = await task.value
    XCTAssertEqual(result?.lifecycle, .launched)
    assertApplicationEventSnapshot(
      result?.application,
      matches: application
    )
  }

  func testApplicationManagerSnapshotStreamsBufferImmediateEventsWithoutReplayingHistory() async {
    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let eventSource = TestApplicationEventSource()
      let runtime = applicationRuntime(eventSource: eventSource)
      let historical = applicationRuntimeEventSnapshot(processIdentifier: 100)
      let first = applicationRuntimeEventSnapshot(processIdentifier: 101)
      let second = applicationRuntimeEventSnapshot(processIdentifier: 102)
      eventSource.emit(lifecycleCase, snapshot: historical)
      let stream = lifecycleCase.applicationSnapshots(from: runtime)

      // All emissions precede the first suspension, including forwarding-task startup.
      eventSource.emit(lifecycleCase.differentLifecycleCase, snapshot: historical)
      eventSource.emit(lifecycleCase, snapshot: first)
      eventSource.emit(lifecycleCase, snapshot: second)

      let received = expectation(description: "\(lifecycleCase.label) immediate events")
      received.expectedFulfillmentCount = 2
      received.assertForOverFulfill = true
      let finished = expectation(description: "\(lifecycleCase.label) consumer stopped")
      var snapshots: [ApplicationSnapshot] = []
      let task = Task { @MainActor in
        defer { finished.fulfill() }
        for await snapshot in stream {
          snapshots.append(snapshot)
          received.fulfill()
        }
      }

      await fulfillment(of: [received], timeout: 1)
      task.cancel()
      await fulfillment(of: [finished], timeout: 1)
      XCTAssertEqual(snapshots, [first, second], lifecycleCase.label)
    }
  }

  func testWorkspaceSnapshotStreamsRegisterImmediatelyAndRemoveObserversAfterCancellation() async {
    let application = NSRunningApplication.current
    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let removed = expectation(description: "\(lifecycleCase.label) observer removed")
      removed.assertForOverFulfill = true
      let center = TestApplicationEventNotificationCenter(observerRemoved: { removed.fulfill() })
      let runtime = applicationRuntime(notificationCenter: center)
      let userInfo = [NSWorkspace.applicationUserInfoKey: application]

      // A notification before subscription must not become fabricated stream history.
      center.post(name: lifecycleCase.notificationName, object: nil, userInfo: userInfo)
      let stream = lifecycleCase.applicationSnapshots(from: runtime)
      XCTAssertEqual(center.observerCount, 1, lifecycleCase.label)
      center.post(name: lifecycleCase.notificationName, object: nil, userInfo: userInfo)

      let received = expectation(description: "\(lifecycleCase.label) immediate notification")
      received.assertForOverFulfill = true
      let finished = expectation(description: "\(lifecycleCase.label) consumer stopped")
      var snapshots: [ApplicationSnapshot] = []
      let task = Task { @MainActor in
        defer { finished.fulfill() }
        for await snapshot in stream {
          snapshots.append(snapshot)
          received.fulfill()
        }
      }

      await fulfillment(of: [received], timeout: 1)
      task.cancel()
      await fulfillment(of: [finished, removed], timeout: 1)
      XCTAssertEqual(snapshots.count, 1, lifecycleCase.label)
      XCTAssertEqual(center.observerCount, 0, lifecycleCase.label)
    }
  }

  func testWorkspaceSnapshotStreamsRemoveObserversWhenCancelledBeforeConsumption() async {
    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let removed = expectation(description: "\(lifecycleCase.label) observer removed")
      removed.assertForOverFulfill = true
      let center = TestApplicationEventNotificationCenter(observerRemoved: { removed.fulfill() })
      let stream = lifecycleCase.applicationSnapshots(
        from: applicationRuntime(notificationCenter: center))
      XCTAssertEqual(center.observerCount, 1, lifecycleCase.label)
      let finished = expectation(description: "\(lifecycleCase.label) consumer stopped")
      var result: ApplicationSnapshot?
      let task = Task { @MainActor in
        defer { finished.fulfill() }
        for await snapshot in stream {
          result = snapshot
          return
        }
      }

      // Cancel before either the consumer or forwarding task can start on the main actor.
      task.cancel()
      await fulfillment(of: [finished, removed], timeout: 1)
      XCTAssertNil(result, lifecycleCase.label)
      XCTAssertEqual(center.observerCount, 0, lifecycleCase.label)
    }
  }

  func testApplicationManagerSnapshotStreamsIgnoreOtherLifecycleEvents() async {
    let application = applicationRuntimeEventSnapshot()

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let eventSource = TestApplicationEventSource()
      let runtime = applicationRuntime(eventSource: eventSource)
      let task = firstValueTask(from: lifecycleCase.applicationSnapshots(from: runtime))

      eventSource.emit(lifecycleCase.differentLifecycleCase, snapshot: application)

      XCTAssertFalse(task.isCancelled, lifecycleCase.label)
      task.cancel()
      let result = await task.value
      XCTAssertNil(result, lifecycleCase.label)
    }
  }

  func testApplicationManagerSnapshotStreamsIgnoreEventsWithoutApplicationSnapshot()
    async
  {
    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let eventSource = TestApplicationEventSource()
      let runtime = applicationRuntime(eventSource: eventSource)
      let task = firstValueTask(from: lifecycleCase.applicationSnapshots(from: runtime))

      eventSource.emit(lifecycleCase, snapshot: nil)

      XCTAssertFalse(task.isCancelled, lifecycleCase.label)
      task.cancel()
      let result = await task.value
      XCTAssertNil(result, lifecycleCase.label)
    }
  }

  func testApplicationManagerSnapshotStreamsStopAfterCancellation() async {
    let application = applicationRuntimeEventSnapshot()

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let eventSource = TestApplicationEventSource()
      let runtime = applicationRuntime(eventSource: eventSource)
      let task = firstValueTask(from: lifecycleCase.applicationSnapshots(from: runtime))

      task.cancel()
      let result = await task.value
      XCTAssertNil(result, lifecycleCase.label)

      eventSource.emit(lifecycleCase, snapshot: application)
    }
  }

  func testApplicationEventsStopsAfterCancellation() async {
    let eventSource = TestApplicationEventSource()
    let application = applicationRuntimeEventSnapshot()
    let runtime = applicationRuntime(eventSource: eventSource)
    let task = firstValueTask(from: runtime.events())

    task.cancel()
    let result = await task.value
    XCTAssertNil(result)

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      eventSource.emit(lifecycleCase, snapshot: application)
    }
  }

  func testApplicationEventSourceFinishesEmptyLifecycleStreams() async {
    let eventSource = TestApplicationEventSource()
    let task = firstValueTask(from: eventSource.eventStream(lifecycles: []))

    let result = await task.value
    XCTAssertNil(result)
  }

  func testWorkspaceApplicationEventSourceFinishesEmptyLifecycleStreams()
    async
  {
    let eventSource = WorkspaceApplicationEventSource(workspace: .shared)
    let task = firstValueTask(from: eventSource.eventStream(lifecycles: []))

    let result = await task.value
    XCTAssertNil(result)
  }

}
