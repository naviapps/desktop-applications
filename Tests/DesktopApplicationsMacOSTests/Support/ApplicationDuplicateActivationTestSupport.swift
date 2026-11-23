import AppKit
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

let duplicateActivationBundleIdentifier = "com.example.app"
let duplicateActivationCurrentProcessIdentifier: pid_t = 100
let duplicateActivationProcessIdentifier: pid_t = 200
let duplicateActivationNotificationName = Notification.Name(
  "test.duplicate-process-activation-request"
)

final class FakeDuplicateActivationRequestTransport:
  ApplicationDuplicateActivationRequestTransport
{
  private final class ObserverToken: NSObject {}

  struct Post: Equatable {
    let name: Notification.Name
    let bundleIdentifier: String
  }

  private(set) var posts: [Post] = []
  private(set) var removedObservers: [ObjectIdentifier] = []

  private var observerTokenCounter = 0
  private struct ObserverEntry {
    let name: Notification.Name
    let bundleIdentifier: String?
    let handler: @MainActor @Sendable () -> Void
  }

  private var observers: [ObjectIdentifier: ObserverEntry] = [:]

  func postActivationRequest(name: Notification.Name, bundleIdentifier: String) {
    posts.append(Post(name: name, bundleIdentifier: bundleIdentifier))
  }

  func observeActivationRequests(
    name: Notification.Name,
    bundleIdentifier: String,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> NSObjectProtocol {
    observerTokenCounter += 1
    let token = ObserverToken()
    observers[ObjectIdentifier(token)] = ObserverEntry(
      name: name,
      bundleIdentifier: bundleIdentifier,
      handler: handler
    )
    return token
  }

  func removeActivationRequestObserver(_ observer: NSObjectProtocol) {
    let token = ObjectIdentifier(observer as AnyObject)
    removedObservers.append(token)
    observers[token] = nil
  }

  @MainActor
  func trigger(name: Notification.Name, bundleIdentifier: String) {
    for (_, entry) in observers {
      guard entry.name == name else { continue }
      if let expectedBundleIdentifier = entry.bundleIdentifier,
        expectedBundleIdentifier != bundleIdentifier
      {
        continue
      }
      entry.handler()
    }
  }
}

final class FakeDuplicateActivationNotificationCenter:
  ApplicationDuplicateActivationNotificationCenter
{
  private final class ObserverToken: NSObject {}

  struct Post: Equatable {
    let name: Notification.Name
    let object: String?
  }

  struct ObserverRegistration {
    let name: Notification.Name?
    let object: String?
    let queue: OperationQueue?
    let block: @Sendable (Notification) -> Void
  }

  private(set) var posts: [Post] = []
  private(set) var observerRegistrations: [ObserverRegistration] = []
  private(set) var removedObservers: [ObjectIdentifier] = []
  private var nextObserver = 0

  func post(name: Notification.Name, object: String?) {
    posts.append(Post(name: name, object: object))
  }

  func addObserver(
    forName name: Notification.Name?,
    object: String?,
    queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol {
    observerRegistrations.append(
      ObserverRegistration(name: name, object: object, queue: queue, block: block)
    )
    nextObserver += 1
    return ObserverToken()
  }

  func removeObserver(_ observer: NSObjectProtocol) {
    removedObservers.append(ObjectIdentifier(observer as AnyObject))
  }
}

@MainActor
final class FakeRunningProcessIdentifiers {
  var identifiers: [pid_t]

  init(_ identifiers: [pid_t]) {
    self.identifiers = identifiers
  }
}

func duplicateActivationPost(
  name: Notification.Name = duplicateActivationNotificationName,
  bundleIdentifier: String = duplicateActivationBundleIdentifier
) -> FakeDuplicateActivationRequestTransport.Post {
  .init(name: name, bundleIdentifier: bundleIdentifier)
}

@MainActor
func makeDuplicateActivationCoordinator(
  bundleIdentifier: String = duplicateActivationBundleIdentifier,
  notificationName: Notification.Name = duplicateActivationNotificationName,
  currentProcessIdentifier: pid_t = duplicateActivationCurrentProcessIdentifier,
  runningProcessIdentifiers: [pid_t],
  transport: FakeDuplicateActivationRequestTransport,
  activateCurrentApplication:
    @escaping @MainActor @Sendable (_ options: NSApplication.ActivationOptions) -> Bool = {
      _ in true
    },
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> ApplicationDuplicateActivationCoordinator {
  try makeDuplicateActivationCoordinator(
    bundleIdentifier: bundleIdentifier,
    notificationName: notificationName,
    currentProcessIdentifier: { currentProcessIdentifier },
    runningProcessIdentifiers: { lookedUpBundleIdentifier in
      XCTAssertEqual(
        lookedUpBundleIdentifier,
        duplicateActivationBundleIdentifier,
        file: file,
        line: line
      )
      return runningProcessIdentifiers
    },
    transport: transport,
    activateCurrentApplication: activateCurrentApplication
  )
}

@MainActor
func makeDuplicateActivationCoordinator(
  bundleIdentifier: String = duplicateActivationBundleIdentifier,
  notificationName: Notification.Name = duplicateActivationNotificationName,
  currentProcessIdentifier:
    @escaping @MainActor @Sendable () -> pid_t =
    {
      duplicateActivationCurrentProcessIdentifier
    },
  runningProcessIdentifiers:
    @escaping @MainActor @Sendable (_ bundleIdentifier: String) -> [pid_t],
  transport: FakeDuplicateActivationRequestTransport,
  activateCurrentApplication:
    @escaping @MainActor @Sendable (_ options: NSApplication.ActivationOptions) -> Bool = {
      _ in true
    }
) throws -> ApplicationDuplicateActivationCoordinator {
  try ApplicationDuplicateActivationCoordinator(
    bundleIdentifier: bundleIdentifier,
    notificationName: notificationName,
    dependencies: ApplicationDuplicateActivationCoordinatorDependencies(
      activateCurrentApplication: activateCurrentApplication,
      currentProcessIdentifier: currentProcessIdentifier,
      runningProcessIdentifiers: runningProcessIdentifiers,
      activationRequestTransport: transport
    )
  )
}
