import AppKit
import DesktopApplications
import Foundation
import Synchronization

@testable import DesktopApplicationsMacOS

/// Observe the real live adapter without replacing or delaying its OS callbacks.
/// The existing SwiftPM debug build enables this internal test seam.
private final class OpeningCallbacks: Sendable {
  private struct State {
    var dispatches: [String: Int] = [:]
    var arrivals: [String: [Bool]] = [:]
    var forwards: [String: Int] = [:]
  }

  private let state = Mutex(State())

  func dispatched(_ key: String) {
    state.withLock { $0.dispatches[key, default: 0] += 1 }
  }

  func arrived(_ key: String, accepted: Bool) {
    state.withLock { $0.arrivals[key, default: []].append(accepted) }
  }

  func forwarded(_ key: String) {
    state.withLock { $0.forwards[key, default: 0] += 1 }
  }

  func dispatchCount(_ key: String) -> Int {
    state.withLock { $0.dispatches[key, default: 0] }
  }

  func results(_ key: String) -> [Bool] {
    state.withLock { $0.arrivals[key, default: []] }
  }

  var allForwarded: Bool {
    state.withLock { state in
      state.dispatches.allSatisfy { state.forwards[$0.key, default: 0] == $0.value }
    }
  }
}

@MainActor
private func stopOwnedApplications(at target: URL, bundleIdentifier: String) async throws {
  func applications() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter {
      $0.bundleURL?.standardizedFileURL == target.standardizedFileURL
    }
  }
  let owned = applications()
  for application in owned where !application.isTerminated {
    try require(
      application.forceTerminate() || application.isTerminated,
      "Fixture cleanup could not terminate its target")
  }
  try await wait(message: "Fixture cleanup left a target process running") {
    owned.allSatisfy(\.isTerminated) && applications().isEmpty
  }
}

@MainActor
func acceptOpeningCancellation(at target: URL, work: URL, bundleIdentifier: String) async throws {
  let root = work.appendingPathComponent(
    "opening-cancellation-" + UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let firstReceipt = root.appendingPathComponent("cancelled.json")
  let nextReceipt = root.appendingPathComponent("next.json")
  let callbacks = OpeningCallbacks()
  let liveOpening = ApplicationManagerDependencies.live().requestConfiguredApplicationOpening
  let manager = ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      requestConfiguredApplicationOpening: { workspace, url, configuration, completion in
        let key = configuration.arguments[0]
        callbacks.dispatched(key)
        if key == firstReceipt.path {
          // Exercise cancellation after the SDK begins its request, before the OS callback.
          withUnsafeCurrentTask { $0?.cancel() }
        }
        liveOpening(workspace, url, configuration) { accepted in
          callbacks.arrived(key, accepted: accepted)
          completion(accepted)
          callbacks.forwarded(key)
        }
      }
    )
  )

  func configuration(receipt: URL) -> NSWorkspace.OpenConfiguration {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [
      receipt.path, "accept", String(ProcessInfo.processInfo.processIdentifier),
    ]
    configuration.createsNewApplicationInstance = true
    configuration.promptsUserIfNeeded = false
    configuration.addsToRecentItems = false
    configuration.activates = false
    return configuration
  }

  func cleanUp() async throws {
    var errors: [String] = []
    do {
      try await wait(message: "Fixture cleanup did not receive all dispatched AppKit callbacks") {
        callbacks.allForwarded
      }
    } catch {
      errors.append(String(describing: error))
    }
    do {
      try await stopOwnedApplications(at: target, bundleIdentifier: bundleIdentifier)
    } catch {
      errors.append(String(describing: error))
    }
    do {
      try FileManager.default.removeItem(at: root)
    } catch {
      errors.append(String(describing: error))
    }
    if !errors.isEmpty {
      throw AcceptanceError.failed("Fixture cleanup: " + errors.joined(separator: "; "))
    }
  }

  do {
    var firstResult: Result<ApplicationRequestResult<ApplicationLaunchError>, any Error>?
    let first = Task { @MainActor in
      do {
        firstResult = .success(
          try await manager.openApplication(
            at: target,
            configuration: configuration(receipt: firstReceipt)))
      } catch {
        firstResult = .failure(error)
      }
    }
    defer { first.cancel() }
    try await wait(timeout: .seconds(2), message: "Cancelled launch wait did not finish") {
      firstResult != nil
    }
    try require(callbacks.dispatchCount(firstReceipt.path) == 1, "Expected one first dispatch")
    try require(
      first.isCancelled, "Expected cancellation at the native dispatch boundary")
    guard case .failure(let error)? = firstResult, error is CancellationError else {
      throw AcceptanceError.failed("Opening returned a launch result instead of CancellationError")
    }

    var nextResult: Result<ApplicationRequestResult<ApplicationLaunchError>, any Error>?
    var nextCompletedBeforeItsCallback = false
    let next = Task { @MainActor in
      do {
        nextResult = .success(
          try await manager.openApplication(
            at: target,
            configuration: configuration(receipt: nextReceipt)))
      } catch {
        nextResult = .failure(error)
      }
      nextCompletedBeforeItsCallback = callbacks.results(nextReceipt.path).isEmpty
    }
    defer { next.cancel() }
    try await wait(message: "Native callbacks and owned targets did not complete") {
      nextResult != nil && callbacks.allForwarded
        && FileManager.default.fileExists(atPath: firstReceipt.path)
        && FileManager.default.fileExists(atPath: nextReceipt.path)
    }
    guard case .failure(let error)? = firstResult, error is CancellationError else {
      throw AcceptanceError.failed("Late AppKit callback replaced the cancelled result")
    }
    try require(callbacks.dispatchCount(nextReceipt.path) == 1, "Expected one next dispatch")
    try require(
      callbacks.results(firstReceipt.path) == [true], "Expected one successful real late callback")
    guard case .success(.requestAccepted)? = nextResult else {
      throw AcceptanceError.failed("The independent next launch was not accepted")
    }
    try require(
      callbacks.results(nextReceipt.path) == [true], "Expected one successful next callback")
    try require(
      !nextCompletedBeforeItsCallback, "Next request finished before its own AppKit callback")
    var processIdentifiers: Set<pid_t> = []
    for receipt in [firstReceipt, nextReceipt] {
      let data = try Data(contentsOf: receipt)
      let record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard let pid = record?["processId"] as? Int32,
        let application = NSRunningApplication(processIdentifier: pid),
        application.bundleIdentifier == bundleIdentifier,
        application.bundleURL?.standardizedFileURL == target.standardizedFileURL
      else {
        throw AcceptanceError.failed("Fixture receipt did not identify its owned running target")
      }
      try require(
        processIdentifiers.insert(pid).inserted, "Fixture launches reused a target process")
    }
  } catch {
    let acceptanceError = error
    do {
      try await cleanUp()
    } catch {
      throw AcceptanceError.failed("\(acceptanceError); fixture cleanup also failed: \(error)")
    }
    throw acceptanceError
  }
  try await cleanUp()
  print(
    "Native macOS cancellation before a real late AppKit callback and independent next launch passed."
  )
}
