import AppKit
import DesktopApplications
import DesktopApplicationsMacOS
import Foundation

enum AcceptanceError: Error { case failed(String) }
func require(_ condition: Bool, _ message: String) throws {
  guard condition else { throw AcceptanceError.failed(message) }
}
@MainActor
func wait(
  timeout: Duration = .seconds(15), message: String = "Native wait timed out",
  _ condition: () -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    guard ContinuousClock.now < deadline else {
      throw AcceptanceError.failed(message)
    }
    try await Task.sleep(for: .milliseconds(50))
  }
}

@MainActor
func run() async throws {
  guard CommandLine.arguments.count == 3 else {
    throw AcceptanceError.failed("Expected fixture app and work directory")
  }
  let target = URL(fileURLWithPath: CommandLine.arguments[1])
  let work = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
  guard let bundle = Bundle(url: target)?.bundleIdentifier,
    bundle.hasPrefix("com.naviapps.desktop-applications.acceptance."),
    target.deletingLastPathComponent().standardizedFileURL == work.standardizedFileURL
  else {
    throw AcceptanceError.failed("Expected a uniquely owned fixture app inside its work root")
  }
  let selection =
    ProcessInfo.processInfo.environment["DESKTOP_APPLICATIONS_ACCEPTANCE_CASE"] ?? "all"
  try require(
    ["all", "opening-cancellation"].contains(selection),
    "Unknown native acceptance case: \(selection)")
  try await acceptOpeningCancellation(at: target, work: work, bundleIdentifier: bundle)
  if selection == "opening-cancellation" { return }
  let manager = ApplicationManager()
  defer {
    for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
      if !application.isTerminated { _ = application.forceTerminate() }
    }
  }
  var events: [ApplicationEvent] = []
  let stream = manager.events()
  let observation = Task { @MainActor in
    for await event in stream where event.application.bundleIdentifier == bundle {
      events.append(event)
    }
  }
  defer { observation.cancel() }
  for mode in ["accept", "refuse"] {
    let receipt = work.appendingPathComponent(mode + ".json")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [receipt.path, mode]
    configuration.createsNewApplicationInstance = true
    let launched = try await manager.openApplication(at: target, configuration: configuration)
    try require(launched == .requestAccepted, "Native launch was rejected")
    try await wait {
      FileManager.default.fileExists(atPath: receipt.path)
        && !manager.runningApplications(bundleIdentifier: bundle).isEmpty
    }
    let snapshot = manager.runningApplications(bundleIdentifier: bundle)[0]
    let owned = NSRunningApplication(processIdentifier: snapshot.processIdentifier)!
    defer { if !owned.isTerminated { _ = owned.forceTerminate() } }
    try require(snapshot.identity.startTime != 0, "Native creation metadata unavailable")
    let stale = ApplicationSnapshot(
      identity: ApplicationProcessIdentity(
        processID: snapshot.identity.processID, startTime: snapshot.identity.startTime + 1),
      identifier: snapshot.identifier)
    try require(
      manager.terminateApplication(stale) == .failed(.processIdentityMismatch),
      "Stale target accepted")
    try require(!owned.isTerminated, "Stale operation changed the owned process")
    _ = manager.activateApplication(snapshot)
    let requested = manager.terminateApplication(snapshot)
    if mode == "accept" {
      try require(requested == .requestAccepted, "Graceful termination request rejected")
      try await wait { owned.isTerminated }
    } else {
      try await wait {
        guard let data = try? Data(contentsOf: receipt),
          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (record["closeRequests"] as? Int ?? 0) > 0
      }
      try require(!owned.isTerminated, "Graceful termination bypassed application refusal")
      try require(
        manager.terminateApplication(snapshot, mode: .forced) == .requestAccepted,
        "Owned force termination rejected")
      try await wait { owned.isTerminated }
    }
    try await wait {
      events.contains {
        $0.application.processIdentifier == snapshot.processIdentifier && $0.lifecycle == .launched
      }
        && events.contains {
          $0.application.processIdentifier == snapshot.processIdentifier
            && $0.lifecycle == .terminated
        }
    }
  }
  print(
    "Native macOS launch, lifecycle events, process identity, graceful refusal and owned termination passed."
  )
}

try await run()
