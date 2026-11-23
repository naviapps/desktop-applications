import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationManagerOpeningCancellationTests: XCTestCase {
  func testCancellationBeforeBeginSkipsDispatchAndResumesOnceDespiteLateCallbacks() async {
    let request = ApplicationOpeningRequest()
    let finished = expectation(description: "cancelled request resumed once")
    finished.assertForOverFulfill = true
    var dispatches = 0
    var resumptions = 0

    // Exercise the state reached when onCancel runs before the continuation is installed.
    request.finish(nil)
    let task = Task { @MainActor in
      let result: Bool? = await withCheckedContinuation { continuation in
        if request.begin(continuation) {
          dispatches += 1
        }
        request.finish(true)
        request.finish(false)
        request.finish(nil)
      }
      resumptions += 1
      finished.fulfill()
      return result
    }
    defer { task.cancel() }

    await fulfillment(of: [finished], timeout: 2)
    XCTAssertEqual(dispatches, 0)
    XCTAssertEqual(resumptions, 1)
    guard resumptions == 1 else { return }
    let result = await task.value
    XCTAssertNil(result)

    // CheckedContinuation also traps any attempt to resume it a second time.
    request.finish(false)
    request.finish(true)
    request.finish(nil)
    XCTAssertEqual(resumptions, 1)
  }

  func testAlreadyCancelledOpeningDoesNotLookUpOrRequestApplication() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    var lookups = 0
    var requests = 0
    let manager = ApplicationManager(
      dependencies: ApplicationManagerDependencies(
        installedApplicationURL: { _, _ in
          lookups += 1
          return applicationURL
        },
        requestConfiguredApplicationOpening: { _, _, _, completion in
          requests += 1
          completion(true)
        }
      )
    )
    for useIdentifier in [true, false] {
      let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        do {
          if useIdentifier {
            _ = try await manager.openApplication(
              bundleIdentifier: "com.example.app", configuration: NSWorkspace.OpenConfiguration())
          } else {
            _ = try await manager.openApplication(
              at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
          }
          return false
        } catch {
          return true
        }
      }
      let wasCancelled = await task.value
      XCTAssertTrue(wasCancelled)
    }
    XCTAssertEqual(lookups, 0)
    XCTAssertEqual(requests, 0)
  }

  func testCancellationDuringValidationPreventsDispatch() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    var requests = 0
    let manager = ApplicationManager(
      dependencies: ApplicationManagerDependencies(
        requestConfiguredApplicationOpening: { _, _, _, completion in
          requests += 1
          completion(true)
        },
        fileExists: { _ in
          withUnsafeCurrentTask { $0?.cancel() }
          return true
        }
      )
    )
    let task = Task { @MainActor in
      do {
        _ = try await manager.openApplication(
          at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
        return false
      } catch {
        return true
      }
    }
    let wasCancelled = await task.value
    XCTAssertTrue(wasCancelled)
    XCTAssertEqual(requests, 0)
  }

  func testCancellationDuringFailedLookupTakesPrecedenceOverValidationFailure() async {
    let manager = ApplicationManager(
      dependencies: ApplicationManagerDependencies(
        installedApplicationURL: { _, _ in
          withUnsafeCurrentTask { $0?.cancel() }
          return nil
        },
        requestConfiguredApplicationOpening: { _, _, _, _ in
          XCTFail("Cancelled validation must not dispatch")
        },
        fileExists: { _ in
          withUnsafeCurrentTask { $0?.cancel() }
          return false
        }
      )
    )
    for useIdentifier in [true, false] {
      let task = Task { @MainActor in
        do {
          if useIdentifier {
            _ = try await manager.openApplication(
              bundleIdentifier: "com.example.missing",
              configuration: NSWorkspace.OpenConfiguration())
          } else {
            _ = try await manager.openApplication(
              at: URL(fileURLWithPath: "/missing.app"),
              configuration: NSWorkspace.OpenConfiguration())
          }
          return false
        } catch {
          return true
        }
      }
      let wasCancelled = await task.value
      XCTAssertTrue(wasCancelled, "identifier: \(useIdentifier)")
    }
  }

  func testLateCallbacksCannotCompleteThePendingNextRequest() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    let started = expectation(description: "opening request dispatched")
    let finished = expectation(description: "cancelled wait completed")
    let nextStarted = expectation(description: "next request dispatched")
    var callback: (@Sendable (Bool) -> Void)?
    var nextCallback: (@Sendable (Bool) -> Void)?
    var requests = 0
    let manager = ApplicationManager(
      dependencies: ApplicationManagerDependencies(
        requestConfiguredApplicationOpening: { _, _, _, completion in
          requests += 1
          if requests == 1 {
            callback = completion
            started.fulfill()
          } else {
            nextCallback = completion
            nextStarted.fulfill()
          }
        }
      )
    )
    let task = Task { @MainActor in
      defer { finished.fulfill() }
      do {
        _ = try await manager.openApplication(
          at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
        return false
      } catch {
        return true
      }
    }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    await fulfillment(of: [finished], timeout: 2)
    let wasCancelled = await task.value
    XCTAssertTrue(wasCancelled)
    var nextFinished = false
    let next = Task { @MainActor in
      defer { nextFinished = true }
      return try await manager.openApplication(
        at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
    defer { next.cancel() }
    await fulfillment(of: [nextStarted], timeout: 2)
    // Deliver old callbacks while the independent next request is pending.
    let complete = try XCTUnwrap(callback)
    complete(true)
    complete(false)
    await Task.yield()
    XCTAssertFalse(nextFinished)
    let completeNext = try XCTUnwrap(nextCallback)
    completeNext(false)
    let nextResult = try await next.value
    XCTAssertEqual(nextResult, .failed(.requestRejected))
    XCTAssertEqual(requests, 2)
  }

  func testCompletedCallbackWinsLaterCancellationAndDuplicateCallbacks() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    for accepted in [true, false] {
      let manager = ApplicationManager(
        dependencies: ApplicationManagerDependencies(
          requestConfiguredApplicationOpening: { _, _, _, completion in
            completion(accepted)
            withUnsafeCurrentTask { $0?.cancel() }
            completion(!accepted)
          }
        )
      )
      let task = Task { @MainActor in
        try await manager.openApplication(
          at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
      }
      let result = try await task.value
      XCTAssertEqual(result, accepted ? .requestAccepted : .failed(.requestRejected))
    }
  }

  func testConcurrentCancellationAndBackgroundCallbackCompleteOnce() async throws {
    let applicationURL = try temporaryApplicationBundleURL()
    defer { removeTemporaryItem(at: applicationURL) }
    for _ in 0..<64 {
      let started = AsyncStream<Void>.makeStream()
      var callback: (@Sendable (Bool) -> Void)?
      let manager = ApplicationManager(
        dependencies: ApplicationManagerDependencies(
          requestConfiguredApplicationOpening: { _, _, _, completion in
            callback = completion
            started.continuation.yield(())
            started.continuation.finish()
          }
        )
      )
      let task = Task { @MainActor in
        try await manager.openApplication(
          at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
      }
      for await _ in started.stream { break }
      let complete = try XCTUnwrap(callback)
      await withTaskGroup(of: Void.self) { group in
        group.addTask { task.cancel() }
        group.addTask { complete(true) }
      }
      switch await task.result {
      case .success(let result): XCTAssertEqual(result, .requestAccepted)
      case .failure(let error): XCTAssertTrue(error is CancellationError)
      }
    }
  }
}
