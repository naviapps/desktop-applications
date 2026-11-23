import DesktopApplications
import XCTest

final class ApplicationEventTests: XCTestCase {
  func testLifecycleAllCasesListsLifecycleOrder() {
    XCTAssertEqual(
      ApplicationEvent.Lifecycle.allCases,
      [.launched, .terminated, .activated, .deactivated]
    )
  }

  func testInitializerAssignsValues() {
    let snapshot = applicationProcessSnapshot()

    let event = ApplicationEvent(lifecycle: .activated, application: snapshot)

    XCTAssertEqual(event.lifecycle, .activated)
    XCTAssertEqual(event.application, snapshot)
  }

  func testHashableUsesValueEquality() {
    let snapshot = applicationProcessSnapshot()
    let event = ApplicationEvent(lifecycle: .activated, application: snapshot)
    let equalEvent = ApplicationEvent(lifecycle: .activated, application: snapshot)
    let otherApplication = ApplicationEvent(
      lifecycle: .activated, application: applicationProcessSnapshot(processIdentifier: 456))
    let otherLifecycle = ApplicationEvent(lifecycle: .deactivated, application: snapshot)

    XCTAssertEqual(event, equalEvent)
    XCTAssertNotEqual(event, otherApplication)
    XCTAssertNotEqual(event, otherLifecycle)
    XCTAssertEqual(Set([event, equalEvent, otherApplication, otherLifecycle]).count, 3)
  }

  func testSendableConformancesAreUsable() {
    assertSendable(ApplicationEvent.Lifecycle.activated)
    assertSendable(
      ApplicationEvent(lifecycle: .activated, application: applicationProcessSnapshot()))
  }

  func testReconciliationDecodesStateAndLifecycleEvents() throws {
    let original = ApplicationSnapshot(
      processIdentifier: 40, bundleIdentifier: "com.example.app", displayName: "Caf\u{e9}",
      startTime: 100)
    let replacement = ApplicationSnapshot(
      processIdentifier: 40, bundleIdentifier: "com.example.app", displayName: "Cafe\u{301}",
      startTime: 101)
    var applications = [original]
    let previous = ApplicationState(applications: applications, frontmost: original.identity)
    let current = ApplicationState(applications: [replacement], frontmost: replacement.identity)
    applications[0] = replacement
    XCTAssertEqual(previous.applications, [original])
    let result = try previous.reconcile(current)

    XCTAssertEqual(Set([result.state, current]).count, 1)
    assertHashableSendable(ApplicationReconciliation.self, result)
    let terminated = try XCTUnwrap(result.events.first { $0.lifecycle == .terminated })
    XCTAssertEqual(
      terminated.application,
      ApplicationSnapshot(
        identity: original.identity, identifier: original.identifier,
        displayName: original.displayName,
        isTerminated: true))
  }

  func testReconciliationPropagatesNativeRejection() {
    let sample = ApplicationState(
      applications: [ApplicationSnapshot(processIdentifier: 40)], frontmost: nil)

    XCTAssertThrowsError(try ApplicationState.empty.reconcile(sample)) { error in
      guard case DesktopApplicationsError.invalidInput("IdentityUnavailable") = error else {
        return XCTFail("Unexpected reconciliation error: \(error)")
      }
    }
  }
}
