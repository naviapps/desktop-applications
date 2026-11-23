import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationEventWaitTests: XCTestCase {
  // Tests that emit before the asynchronous waiter subscribes explicitly opt in to buffered input.
  // Live notification timing is covered separately by ApplicationEventsTests.
  func testApplicationManagerLifecycleCasesReturnNilOnTimeout() async {
    let eventSource = TestApplicationEventSource()
    let runtime = applicationRuntime(eventSource: eventSource)

    for wait in ApplicationManagerLifecycleCase.allCases {
      let result = await wait.waitForSnapshot(
        from: runtime,
        bundleIdentifier: Self.missingBundleIdentifier,
        timeout: Self.shortTimeout
      )

      XCTAssertNil(result, wait.label)
    }
  }

  func testWaitForApplicationEventReturnsNilOnTimeout() async {
    let eventSource = TestApplicationEventSource()
    let runtime = applicationRuntime(eventSource: eventSource)
    let result = await runtime.waitForApplicationEvent(
      .activated,
      bundleIdentifier: Self.missingBundleIdentifier,
      timeout: Self.shortTimeout
    )

    XCTAssertNil(result)
  }

  func testExpiredAndAlreadyCancelledEventWaitsSkipSubscription() async {
    let runtime = ApplicationManager(
      dependencies: ApplicationManagerDependencies(eventSource: { _ in
        XCTFail("An expired or cancelled wait should not subscribe")
        return InertApplicationEventSource()
      }))
    for timeout in [Duration.zero, .milliseconds(-1)] {
      let result = await runtime.waitForApplicationEvent(
        .activated, bundleIdentifier: "com.example.event", timeout: timeout)
      XCTAssertNil(result)
    }

    let task = applicationRuntimeEventWaitTask(
      runtime: runtime, lifecycle: .activated, bundleIdentifier: "com.example.event",
      timeout: Self.longTimeout)
    task.cancel()
    let result = await task.value
    XCTAssertNil(result)
  }

  func testEventDeadlineIncludesObserverSetup() async {
    let source = TestApplicationEventSource(replaysPastEvents: true)
    let application = applicationRuntimeEventSnapshot()
    let runtime = ApplicationManager(
      dependencies: ApplicationManagerDependencies(eventSource: { _ in
        Thread.sleep(forTimeInterval: 0.2)
        source.emit(.activation, snapshot: application)
        return source
      }))

    let result = await runtime.waitForApplicationEvent(
      .activated, bundleIdentifier: "com.example.event", timeout: .milliseconds(100))

    XCTAssertNil(result)
  }

  func testVeryLongEventWaitRemainsCancellable() async throws {
    let source = TestApplicationEventSource()
    let subscribed = expectation(description: "Long wait selected its observer")
    let runtime = ApplicationManager(
      dependencies: ApplicationManagerDependencies(eventSource: { _ in
        subscribed.fulfill()
        return source
      }))
    let task = applicationRuntimeEventWaitTask(
      runtime: runtime, lifecycle: .activated, bundleIdentifier: "com.example.event",
      timeout: .seconds(Int64.max))
    defer { task.cancel() }
    await fulfillment(of: [subscribed], timeout: 2)
    try await Task.sleep(for: .milliseconds(25))
    task.cancel()
    let result = await task.value
    XCTAssertNil(result)
  }

  func testWaitForApplicationEventReturnsTheMatchingBufferedEvent() async {
    let eventSource = TestApplicationEventSource(replaysPastEvents: true)
    let bundleIdentifier = "com.example.event"
    let application = applicationRuntimeEventSnapshot(bundleIdentifier: bundleIdentifier)
    let unrelated = applicationRuntimeEventSnapshot(bundleIdentifier: Self.missingBundleIdentifier)
    eventSource.emit(.launch, snapshot: application)
    eventSource.emit(.activation, snapshot: unrelated)
    eventSource.emit(.activation, snapshot: application)

    let result = await applicationRuntime(eventSource: eventSource).waitForApplicationEvent(
      .activated, bundleIdentifier: " \(bundleIdentifier)\n", timeout: Self.longTimeout
    )

    XCTAssertEqual(result, ApplicationEvent(lifecycle: .activated, application: application))
  }

  func testWaitForApplicationEventPreservesCanonicalBundleMatching() async {
    let source = TestApplicationEventSource(replaysPastEvents: true)
    let application = applicationRuntimeEventSnapshot(
      bundleIdentifier: "com.example.cafe\u{0301}", isTerminated: true)
    source.emit(.termination, snapshot: application)

    let result = await applicationRuntime(eventSource: source).waitForApplicationTermination(
      bundleIdentifier: " com.example.café ", timeout: Self.longTimeout)

    XCTAssertEqual(result, application)
  }

  func testWaitForApplicationEventIgnoresEventsWithoutApplicationSnapshot()
    async throws
  {
    let eventSource = TestApplicationEventSource(replaysPastEvents: true)
    let application = applicationRuntimeEventSnapshot()
    let bundleIdentifier = application.bundleIdentifier!
    let runtime = applicationRuntime(eventSource: eventSource)
    let task = applicationRuntimeEventWaitTask(
      runtime: runtime,
      lifecycle: .activated,
      bundleIdentifier: bundleIdentifier,
      timeout: Self.longTimeout
    )

    eventSource.emit(.activation, snapshot: nil)
    eventSource.emit(.activation, snapshot: application)

    let result = await task.value
    XCTAssertEqual(result?.lifecycle, .activated)
    XCTAssertEqual(result?.application.bundleIdentifier, bundleIdentifier)
  }

  func testApplicationManagerLifecycleCasesReturnNilForBlankBundleIdentifier() async {
    let eventSource = TestApplicationEventSource()
    let runtime = applicationRuntime(eventSource: eventSource)

    for wait in ApplicationManagerLifecycleCase.allCases {
      let result = await wait.waitForSnapshot(
        from: runtime,
        bundleIdentifier: "   ",
        timeout: Self.longTimeout
      )

      XCTAssertNil(result, wait.label)
    }
  }

  func testWaitForApplicationEventReturnsNilForBlankBundleIdentifier() async {
    let eventSource = TestApplicationEventSource()
    let runtime = applicationRuntime(eventSource: eventSource)
    let result = await runtime.waitForApplicationEvent(
      .activated,
      bundleIdentifier: "   ",
      timeout: Self.longTimeout
    )

    XCTAssertNil(result)
  }

  func testApplicationManagerLifecycleCasesContinueAfterDifferentLifecycle() async {
    let eventSource = TestApplicationEventSource(replaysPastEvents: true)
    let application = applicationRuntimeEventSnapshot()
    let bundleIdentifier = application.bundleIdentifier!
    let runtime = applicationRuntime(eventSource: eventSource)

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let task = lifecycleCase.waitForSnapshotTask(
        from: runtime,
        bundleIdentifier: bundleIdentifier,
        timeout: Self.longTimeout
      )

      eventSource.emit(lifecycleCase.differentLifecycleCase, snapshot: application)
      eventSource.emit(lifecycleCase, snapshot: application)

      let result = await task.value
      XCTAssertEqual(result?.bundleIdentifier, bundleIdentifier, lifecycleCase.label)
    }
  }

  func testApplicationManagerLifecycleCasesReturnMatchingApplication() async {
    let eventSource = TestApplicationEventSource(replaysPastEvents: true)
    let application = applicationRuntimeEventSnapshot()
    let bundleIdentifier = application.bundleIdentifier!
    let runtime = applicationRuntime(eventSource: eventSource)

    for lifecycleCase in ApplicationManagerLifecycleCase.allCases {
      let task = lifecycleCase.waitForSnapshotTask(
        from: runtime,
        bundleIdentifier: " \(bundleIdentifier)\n",
        timeout: Self.longTimeout
      )

      eventSource.emit(lifecycleCase, snapshot: application)

      let result = await task.value
      XCTAssertEqual(result?.bundleIdentifier, bundleIdentifier, lifecycleCase.label)
    }
  }

  private static let missingBundleIdentifier = "com.example.missing.app"
  private static let shortTimeout = Duration.milliseconds(50)
  private static let longTimeout = Duration.seconds(1)
}
