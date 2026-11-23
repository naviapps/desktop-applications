import DesktopApplications
import DesktopApplicationsMacOS
import Foundation

private struct AcceptanceFailure: Error {
  let message: String
}

private func require(_ condition: Bool, _ message: String) throws {
  guard condition else { throw AcceptanceFailure(message: message) }
}

@main
struct DesktopApplicationsConsumer {
  @MainActor
  static func main() async throws {
    try verifyNamedInstallationLookup()
    try await verifyEventWaitTimeouts()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: " com.example.consumer ")
    try require(identifier.value == "com.example.consumer", "Identifier normalization failed")

    let identity = ApplicationResourceIdentity(
      identifier: identifier, location: "/synthetic/Consumer.app", revision: "1", variant: "name")
    let cache = ApplicationResourceCache<String>()
    var loads = 0
    let first = try cache.value(for: identity) {
      loads += 1
      return "Consumer 日本語"
    }
    let invalid = try JSONDecoder().decode(
      ApplicationIdentifier.self, from: Data(#"{"kind":"bundle","value":" \t"}"#.utf8))
    do {
      try cache.invalidate(identifier: invalid)
      throw AcceptanceFailure(message: "Packaged cache accepted an invalid identifier")
    } catch DesktopApplicationsError.invalidInput("InvalidIdentifier") {}
    let cached = try cache.value(for: identity) {
      loads += 1
      return "Unexpected reload"
    }
    try require(first == "Consumer 日本語" && cached == first && loads == 1, "Cache hit failed")
    try cache.invalidate(identifier: identifier)
    let reloaded = try cache.value(for: identity) {
      loads += 1
      return "Reloaded"
    }
    try require(reloaded == "Reloaded" && loads == 2, "Cache invalidation failed")

    let recorded = ApplicationSnapshot(
      identity: ApplicationProcessIdentity(processID: 123, startTime: 456), identifier: identifier)
    let matching = try recorded.validationError(against: recorded)
    try require(matching == nil, "Matching synthetic process identity was rejected")
    let replacement = ApplicationSnapshot(
      identity: ApplicationProcessIdentity(processID: 123, startTime: 789), identifier: identifier,
      displayName: "Caf\u{e9}")
    let rejected = try recorded.validationError(against: replacement)
    try require(rejected == .targetChanged, "Reused synthetic process identity was accepted")

    let current = ApplicationState(applications: [replacement], frontmost: replacement.identity)
    let reconciled = try ApplicationState.empty.reconcile(current)
    try require(
      reconciled.state == current && reconciled.events.map(\.lifecycle) == [.launched, .activated],
      "Packaged lifecycle reconciliation failed")

    let revisedName = ApplicationSnapshot(
      identity: replacement.identity, identifier: identifier, displayName: "Cafe\u{301}")
    let next = ApplicationState(applications: [revisedName], frontmost: revisedName.identity)
    let metadataChange = try current.reconcile(next)
    try require(
      metadataChange.state == next && metadataChange.state != current
        && metadataChange.events.isEmpty,
      "Packaged snapshot equality ignored display name spelling")

    print("Standalone DesktopApplications and DesktopApplicationsMacOS acceptance passed.")
  }

  @MainActor
  private static func verifyEventWaitTimeouts() async throws {
    let manager = ApplicationManager()
    let identifier = "com.example.consumer.\(UUID().uuidString)"
    let expiredWait = await manager.waitForApplicationLaunch(
      bundleIdentifier: identifier, timeout: .zero)
    try require(expiredWait == nil, "Expired event wait returned an application")

    let longWait = Task {
      await manager.waitForApplicationLaunch(
        bundleIdentifier: identifier, timeout: .seconds(Int64.max))
    }
    defer { longWait.cancel() }
    try await Task.sleep(for: .milliseconds(50))
    longWait.cancel()
    let cancelled = await longWait.value
    try require(cancelled == nil, "Cancelled event wait returned an application")
  }

  @MainActor
  private static func verifyNamedInstallationLookup() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: directory) }
    let name = "Consumer.app"
    let application = directory.appendingPathComponent(name)
    try files.createDirectory(at: application, withIntermediateDirectories: true)
    let manager = ApplicationManager()
    let found = manager.installedApplicationURL(named: name, searchDirectories: [directory.path])
    try require(
      found?.standardizedFileURL.path == application.path, "Owned application was not found")
    let malformedName = manager.installedApplicationURL(
      named: name + "\0", searchDirectories: [directory.path])
    let malformedDirectory = manager.installedApplicationURL(
      named: name, searchDirectories: [directory.path + "\0"])
    try require(malformedName == nil && malformedDirectory == nil, "Invalid input selected a path")
  }
}
