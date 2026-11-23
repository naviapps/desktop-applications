import AppKit
import DesktopApplications
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationDuplicateActivationCoordinatorTests: XCTestCase {
  func testCoordinateTrimsNotificationName() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      notificationName: Notification.Name("  test.duplicate-process-activation-request\n"),
      runningProcessIdentifiers: [
        duplicateActivationCurrentProcessIdentifier, duplicateActivationProcessIdentifier,
      ],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .duplicate)
    XCTAssertEqual(
      transport.posts,
      [
        .init(
          name: duplicateActivationNotificationName,
          bundleIdentifier: duplicateActivationBundleIdentifier
        )
      ]
    )
  }

  func testCoordinateTrimsBundleIdentifier() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      bundleIdentifier: "  \(duplicateActivationBundleIdentifier)\n",
      runningProcessIdentifiers: [
        duplicateActivationCurrentProcessIdentifier, duplicateActivationProcessIdentifier,
      ],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .duplicate)
    XCTAssertEqual(transport.posts, [duplicateActivationPost()])
  }

  func testCoordinateWhenDuplicatePostsAndReturnsDuplicate() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [
        duplicateActivationCurrentProcessIdentifier, duplicateActivationProcessIdentifier,
      ],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .duplicate)
    XCTAssertEqual(transport.posts, [duplicateActivationPost()])
  }

  func testCoordinateIgnoresInvalidProcessIdentifiers() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [0, -1, duplicateActivationCurrentProcessIdentifier],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .unique)
    XCTAssertTrue(transport.posts.isEmpty)
  }

  func testCoordinateWithInvalidCurrentProcessIdentifierDetectsDuplicate()
    throws
  {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      currentProcessIdentifier: 0,
      runningProcessIdentifiers: [duplicateActivationProcessIdentifier],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .duplicate)
    XCTAssertEqual(transport.posts, [duplicateActivationPost()])
  }

  func testCoordinateWithInvalidCurrentProcessIdentifierIgnoresInvalidCandidates()
    throws
  {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      currentProcessIdentifier: 0,
      runningProcessIdentifiers: [0, -1],
      transport: transport
    )

    let result = coordinator.coordinate(onDuplicateActivationRequest: {})

    XCTAssertEqual(result, .unique)
    XCTAssertTrue(transport.posts.isEmpty)
  }

  func testCoordinateWhenUniqueRegistersObserverAndCallbackRuns() async throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let expectation = expectation(
      description: "duplicate-process activation request callback runs"
    )
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [duplicateActivationCurrentProcessIdentifier],
      transport: transport
    )

    let result = coordinator.coordinate {
      expectation.fulfill()
    }
    XCTAssertEqual(result, .unique)

    transport.trigger(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier)
    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testCoordinateActivatingCurrentApplicationRegistersActivationCallback() async throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let expectation = expectation(description: "current application is activated")
    var activationOptions: [NSApplication.ActivationOptions] = []
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [duplicateActivationCurrentProcessIdentifier],
      transport: transport,
      activateCurrentApplication: { options in
        activationOptions.append(options)
        expectation.fulfill()
        return true
      }
    )

    let result = coordinator.coordinateActivatingCurrentApplication(options: [.activateAllWindows])
    XCTAssertEqual(result, .unique)

    transport.trigger(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier)
    await fulfillment(of: [expectation], timeout: 1.0)

    XCTAssertEqual(activationOptions, [.activateAllWindows])
  }

  func testCoordinateActivatingCurrentApplicationDoesNotActivateDuplicateProcess() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    var activationRequestCount = 0
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [
        duplicateActivationCurrentProcessIdentifier, duplicateActivationProcessIdentifier,
      ],
      transport: transport,
      activateCurrentApplication: { _ in
        activationRequestCount += 1
        return true
      }
    )

    let result = coordinator.coordinateActivatingCurrentApplication()

    XCTAssertEqual(result, .duplicate)
    XCTAssertEqual(activationRequestCount, 0)
    XCTAssertEqual(transport.posts, [duplicateActivationPost()])
  }

  func testCoordinateActivatingCurrentApplicationDoesNotRetainCoordinator() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    weak var weakCoordinator: ApplicationDuplicateActivationCoordinator?

    do {
      let coordinator = try makeDuplicateActivationCoordinator(
        runningProcessIdentifiers: [duplicateActivationCurrentProcessIdentifier],
        transport: transport
      )
      weakCoordinator = coordinator

      XCTAssertEqual(coordinator.coordinateActivatingCurrentApplication(), .unique)
    }

    XCTAssertNil(weakCoordinator)
    XCTAssertEqual(transport.removedObservers.count, 1)
  }

  func testStopRemovesObserver() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [],
      transport: transport
    )

    _ = coordinator.coordinate(onDuplicateActivationRequest: {})
    coordinator.stop()

    XCTAssertEqual(transport.removedObservers.count, 1)
  }

  func testStopPreventsFutureActivationRequests() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [],
      transport: transport
    )

    var activationCount = 0
    _ = coordinator.coordinate {
      activationCount += 1
    }
    coordinator.stop()

    transport.trigger(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier)

    XCTAssertEqual(activationCount, 0)
    XCTAssertEqual(transport.removedObservers.count, 1)
  }

  func testRepeatedCoordinateReplacesObserver() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [],
      transport: transport
    )

    XCTAssertEqual(coordinator.coordinate(onDuplicateActivationRequest: {}), .unique)
    XCTAssertEqual(coordinator.coordinate(onDuplicateActivationRequest: {}), .unique)

    XCTAssertEqual(transport.removedObservers.count, 1)
  }

  func testRepeatedCoordinateDoesNotRunReplacedObserver() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [],
      transport: transport
    )

    var firstActivationCount = 0
    var secondActivationCount = 0

    XCTAssertEqual(
      coordinator.coordinate {
        firstActivationCount += 1
      },
      .unique
    )
    XCTAssertEqual(
      coordinator.coordinate {
        secondActivationCount += 1
      },
      .unique
    )

    transport.trigger(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier)

    XCTAssertEqual(firstActivationCount, 0)
    XCTAssertEqual(secondActivationCount, 1)
    XCTAssertEqual(transport.removedObservers.count, 1)
  }

  func testDuplicateCoordinateRemovesExistingObserver() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let runningProcessIdentifiers = FakeRunningProcessIdentifiers([
      duplicateActivationCurrentProcessIdentifier
    ])
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: { _ in runningProcessIdentifiers.identifiers },
      transport: transport
    )

    XCTAssertEqual(coordinator.coordinate(onDuplicateActivationRequest: {}), .unique)

    runningProcessIdentifiers.identifiers = [
      duplicateActivationCurrentProcessIdentifier,
      duplicateActivationProcessIdentifier,
    ]
    XCTAssertEqual(coordinator.coordinate(onDuplicateActivationRequest: {}), .duplicate)

    XCTAssertEqual(transport.removedObservers.count, 1)
    XCTAssertEqual(transport.posts, [duplicateActivationPost()])
  }

  func testStopIsIdempotentWithoutObserver() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [],
      transport: transport
    )

    coordinator.stop()
    coordinator.stop()

    XCTAssertTrue(transport.removedObservers.isEmpty)
  }

  func testObserverIgnoresDifferentBundleIdentifier() throws {
    let transport = FakeDuplicateActivationRequestTransport()
    let coordinator = try makeDuplicateActivationCoordinator(
      runningProcessIdentifiers: [duplicateActivationCurrentProcessIdentifier],
      transport: transport
    )

    var activationCount = 0
    let result = coordinator.coordinate {
      activationCount += 1
    }
    XCTAssertEqual(result, .unique)

    transport.trigger(
      name: duplicateActivationNotificationName, bundleIdentifier: "com.example.other")

    XCTAssertEqual(activationCount, 0)
  }

  func testDistributedNotificationTransportPostsBundleIdentifierObject() {
    let notificationCenter = FakeDuplicateActivationNotificationCenter()
    let transport = DistributedNotificationActivationRequestTransport(
      notificationCenter: notificationCenter
    )

    transport.postActivationRequest(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier
    )

    XCTAssertEqual(
      notificationCenter.posts,
      [
        .init(
          name: duplicateActivationNotificationName, object: duplicateActivationBundleIdentifier)
      ]
    )
  }

  func testDistributedNotificationTransportObservesMainQueueWithBundleIdentifierObject()
    async
  {
    let notificationCenter = FakeDuplicateActivationNotificationCenter()
    let transport = DistributedNotificationActivationRequestTransport(
      notificationCenter: notificationCenter
    )
    var activationCount = 0

    _ = transport.observeActivationRequests(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier
    ) {
      activationCount += 1
    }

    let observerRegistration = try? XCTUnwrap(notificationCenter.observerRegistrations.first)
    XCTAssertEqual(observerRegistration?.name, duplicateActivationNotificationName)
    XCTAssertEqual(observerRegistration?.object, duplicateActivationBundleIdentifier)
    XCTAssertTrue(observerRegistration?.queue === OperationQueue.main)

    observerRegistration?.block(Notification(name: duplicateActivationNotificationName))
    await Task.yield()

    XCTAssertEqual(activationCount, 1)
  }

  func testDistributedNotificationTransportRemovesActivationRequestObserver() throws {
    let notificationCenter = FakeDuplicateActivationNotificationCenter()
    let transport = DistributedNotificationActivationRequestTransport(
      notificationCenter: notificationCenter
    )
    let observer = transport.observeActivationRequests(
      name: duplicateActivationNotificationName,
      bundleIdentifier: duplicateActivationBundleIdentifier
    ) {}

    transport.removeActivationRequestObserver(observer)

    XCTAssertEqual(
      notificationCenter.removedObservers, [ObjectIdentifier(observer as AnyObject)])
  }
}
