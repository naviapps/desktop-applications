import AppKit
import DesktopApplications
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
final class ApplicationResourcesTests: XCTestCase {
  func testInvalidIdentifierDoesNotClearUnrelatedResources() {
    let first = "com.example.first"
    let second = "com.example.second"
    var loads = 0
    let resources = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in nil },
        installedApplicationURL: { URL(fileURLWithPath: "/\($0).app") },
        displayName: { _ in
          loads += 1
          return "Revision \(loads)"
        },
        icon: { _ in nil },
        identity: { identifier, url, variant in
          ApplicationResourceIdentity(
            identifier: identifier, location: url.path, revision: "1", variant: variant)
        }))
    XCTAssertEqual(resources.displayName(forBundleIdentifier: first), "Revision 1")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: second), "Revision 2")

    for malformed in [" \n", "com.example\0.app"] {
      resources.invalidate(bundleIdentifier: malformed)
      XCTAssertEqual(resources.displayName(forBundleIdentifier: first), "Revision 1")
      XCTAssertEqual(resources.displayName(forBundleIdentifier: second), "Revision 2")
    }

    resources.invalidate(bundleIdentifier: " \(first)\n")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: first), "Revision 3")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: second), "Revision 2")
    resources.invalidate()
    XCTAssertEqual(resources.displayName(forBundleIdentifier: first), "Revision 4")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: second), "Revision 5")
  }

  func testCopiesRevisionsMissingInstallationsAndInvalidationReloadNativeIcons() throws {
    let first = URL(fileURLWithPath: "/selected.app")
    var installed: URL? = first
    var revision = "1"
    var loads = 0
    let image = NSImage(size: NSSize(width: 16, height: 16))
    let resources = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in nil }, installedApplicationURL: { _ in installed },
        displayName: { _ in nil },
        icon: { _ in
          loads += 1
          return image
        },
        identity: { identifier, url, variant in
          ApplicationResourceIdentity(
            identifier: identifier, location: url.path, revision: revision, variant: variant)
        }))
    XCTAssertTrue(resources.icon(forBundleIdentifier: "com.example.app") === image)
    XCTAssertTrue(resources.icon(forBundleIdentifier: "com.example.app") === image)
    XCTAssertEqual(loads, 1)
    installed = URL(fileURLWithPath: "/another.app")
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    revision = "2"
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    resources.invalidate(bundleIdentifier: "com.example.app")
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    installed = nil
    XCTAssertNil(resources.icon(forBundleIdentifier: "com.example.app"))
    installed = first
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertEqual(loads, 5)
    resources.invalidate()
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertEqual(loads, 6)
  }

  func testRunningDisplayNameIsFreshAndDoesNotReplaceExplicitBundleName() throws {
    var running: String? = "Running Copy"
    var installed: URL? = URL(fileURLWithPath: "/registered.app")
    let resources = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in running }, installedApplicationURL: { _ in installed },
        displayName: { _ in "Registered Copy" }, icon: { _ in nil },
        identity: { identifier, url, variant in
          ApplicationResourceIdentity(
            identifier: identifier, location: url.path, revision: "1", variant: variant)
        }))
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), "Running Copy")
    running = "Renamed Running Copy"
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), running)
    running = " \n"
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), "Registered Copy")
    running = nil
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), "Registered Copy")
    installed = nil
    XCTAssertNil(resources.displayName(forBundleIdentifier: "com.example.app"))
    XCTAssertNil(resources.displayName(forBundleIdentifier: " \n"))
  }

  func testMissingNativeIconIsRetriedWithoutCachingFallback() {
    var loads = 0
    let resources = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in nil },
        installedApplicationURL: { _ in URL(fileURLWithPath: "/selected.app") },
        displayName: { _ in nil },
        icon: { _ in
          loads += 1
          return loads == 1 ? nil : NSImage(size: NSSize(width: 16, height: 16))
        },
        identity: { identifier, url, variant in
          ApplicationResourceIdentity(
            identifier: identifier, location: url.path, revision: "1", variant: variant)
        }))
    XCTAssertNil(resources.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertNotNil(resources.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertEqual(loads, 2)
  }

  func testRemovedInstallationReturnsNoResourcesAndReinstallationIsReadFresh() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appendingPathComponent("Fixture.app")
    let identifier = "com.example.resources.fixture"
    func install(_ name: String) throws {
      try FileManager.default.createDirectory(
        at: application.appendingPathComponent("Contents"), withIntermediateDirectories: true)
      let info = [
        "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL",
        "CFBundleDisplayName": name,
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: application.appendingPathComponent("Contents/Info.plist"))
    }
    try install("Installed Copy")
    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    dependencies.runningDisplayName = { _ in nil }
    // Keep a stale registry location after removal without registering a fixture app.
    dependencies.installedApplicationURL = { _ in application }
    let resources = ApplicationResources(dependencies: dependencies)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier), "Installed Copy")
    XCTAssertNotNil(resources.icon(forBundleIdentifier: identifier))

    try FileManager.default.removeItem(at: application)
    XCTAssertNil(resources.displayName(forBundleIdentifier: identifier))
    XCTAssertNil(resources.icon(forBundleIdentifier: identifier))

    try install("Reinstalled Copy")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier), "Reinstalled Copy")
    XCTAssertNotNil(resources.icon(forBundleIdentifier: identifier))
  }

  func testInstalledResourcesRejectReplacedBundleAndRecoverOriginalIdentifier() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Selected.app")
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = application.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = contents.appendingPathComponent("Info.plist")
    let original = "com.example.resources.a"
    func install(_ identifier: String, name: String, time: TimeInterval) throws {
      let info = [
        "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL",
        "CFBundleDisplayName": name,
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: plist, options: .atomic)
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: plist.path)
    }

    let originalIcon = NSImage(size: NSSize(width: 16, height: 16))
    let replacementIcon = NSImage(size: NSSize(width: 32, height: 32))
    let restoredIcon = NSImage(size: NSSize(width: 64, height: 64))
    var icon = originalIcon
    var runningName: String?
    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    // Keep Launch Services' stale result without registering or launching these fixtures.
    dependencies.installedApplicationURL = { _ in application }
    dependencies.runningDisplayName = { _ in runningName }
    dependencies.icon = { _ in icon }
    let resources = ApplicationResources(dependencies: dependencies)

    try install(original, name: "Original App", time: 1_000)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: original), "Original App")
    XCTAssertTrue(resources.icon(forBundleIdentifier: original) === originalIcon)

    try install("com.example.resources.b", name: "Replacement App", time: 2_000)
    icon = replacementIcon
    XCTAssertNil(
      resources.displayName(forBundleIdentifier: original),
      "A stale registration must not display the replacement application's name.")
    XCTAssertNil(
      resources.icon(forBundleIdentifier: original),
      "A stale registration must not display the replacement application's icon.")
    runningName = "Running Original"
    XCTAssertEqual(resources.displayName(forBundleIdentifier: original), runningName)
    runningName = nil

    try install(original, name: "Restored App", time: 3_000)
    icon = restoredIcon
    XCTAssertEqual(resources.displayName(forBundleIdentifier: original), "Restored App")
    XCTAssertTrue(resources.icon(forBundleIdentifier: original) === restoredIcon)
  }

  func testUncacheableInstalledResourcesRejectMismatchButKeepUnavailableMetadataFallback() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Selected.app")
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = application.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = contents.appendingPathComponent("Info.plist")
    let info = [
      "CFBundleIdentifier": "com.example.resources.b", "CFBundlePackageType": "APPL",
      "CFBundleDisplayName": "Replacement App",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: plist)
    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    dependencies.installedApplicationURL = { _ in application }
    dependencies.runningDisplayName = { _ in nil }
    dependencies.identity = { _, _, _ in nil }
    var iconLoads = 0
    dependencies.icon = { _ in
      iconLoads += 1
      return NSImage(size: NSSize(width: 16, height: 16))
    }
    let resources = ApplicationResources(dependencies: dependencies)
    let original = "com.example.resources.a"

    XCTAssertNil(resources.displayName(forBundleIdentifier: original))
    XCTAssertNil(resources.icon(forBundleIdentifier: original))
    XCTAssertEqual(iconLoads, 0)

    try FileManager.default.removeItem(at: plist)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: original), "Selected")
    XCTAssertNotNil(resources.icon(forBundleIdentifier: original))
    XCTAssertEqual(iconLoads, 1)
  }

  func testInstalledResourcesUseAndRefreshMacOSSpecificMetadata() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: url) }
    let contents = url.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let platformPlist = contents.appendingPathComponent("Info-macos.plist")
    let identifier = "com.example.platform"
    let baseIdentifier = "com.example.base"
    func writeInfo(to plist: URL, identifier: String, name: String) throws {
      try PropertyListSerialization.data(
        fromPropertyList: [
          "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL",
          "CFBundleDisplayName": name,
        ], format: .xml, options: 0
      ).write(to: plist, options: .atomic)
    }
    try writeInfo(
      to: contents.appendingPathComponent("Info.plist"), identifier: baseIdentifier,
      name: "Base Name")
    try writeInfo(to: platformPlist, identifier: identifier, name: "Platform Name")
    let bundle = try XCTUnwrap(Bundle(url: url))
    XCTAssertEqual(bundle.bundleIdentifier, identifier)
    XCTAssertEqual(
      ApplicationBundleDisplayName.displayName(for: bundle, applicationURL: url), "Platform Name")

    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    dependencies.runningDisplayName = { _ in nil }
    // Simulate a registered URL without registering or launching a real application.
    dependencies.installedApplicationURL = { _ in url }
    let icon = NSImage()
    dependencies.icon = { _ in icon }
    let resources = ApplicationResources(dependencies: dependencies)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier), "Platform Name")
    XCTAssertTrue(resources.icon(forBundleIdentifier: identifier) === icon)
    XCTAssertNil(resources.displayName(forBundleIdentifier: baseIdentifier))
    XCTAssertNil(resources.icon(forBundleIdentifier: baseIdentifier))

    try writeInfo(to: platformPlist, identifier: identifier, name: "Renamed App")
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier), "Renamed App")

    try FileManager.default.removeItem(at: platformPlist)
    XCTAssertNil(resources.displayName(forBundleIdentifier: identifier))
    XCTAssertNil(resources.icon(forBundleIdentifier: identifier))
    XCTAssertEqual(resources.displayName(forBundleIdentifier: baseIdentifier), "Base Name")
    XCTAssertTrue(resources.icon(forBundleIdentifier: baseIdentifier) === icon)
  }

  func testLifecycleAndLocaleInvalidationAreOwnedBySDKAndObserversRelease() {
    let workspace = NotificationCenter()
    let locale = NotificationCenter()
    var loads = 0
    var resources: ApplicationResources? = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in nil },
        installedApplicationURL: { _ in URL(fileURLWithPath: "/selected.app") },
        displayName: { _ in nil },
        icon: { _ in
          loads += 1
          return NSImage()
        },
        identity: { identifier, url, variant in
          ApplicationResourceIdentity(
            identifier: identifier, location: url.path, revision: "1", variant: variant)
        }), workspaceNotificationCenter: workspace, localeNotificationCenter: locale)
    weak let released = resources
    XCTAssertNotNil(resources?.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertNotNil(resources?.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertEqual(loads, 1)
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      workspace.post(name: name, object: nil)
      XCTAssertNotNil(resources?.icon(forBundleIdentifier: "com.example.app"))
    }
    locale.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    XCTAssertNotNil(resources?.icon(forBundleIdentifier: "com.example.app"))
    XCTAssertEqual(loads, 4)
    resources = nil
    XCTAssertNil(released)
    workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    XCTAssertEqual(loads, 4)
  }

  func testNativeRevisionReadsChangedPlistBytesWithinOneSecond() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist = root.appendingPathComponent("Contents/Info.plist")
    func write(_ name: String, time: TimeInterval) throws {
      let info = [
        "CFBundleIdentifier": "com.example.app", "CFBundlePackageType": "APPL",
        "CFBundleDisplayName": name,
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
        to: plist)
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: plist.path)
    }
    try write("First Name", time: 1000.001)
    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    dependencies.runningDisplayName = { _ in nil }
    dependencies.installedApplicationURL = { _ in root }
    let resources = ApplicationResources(dependencies: dependencies)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), "First Name")
    try write("Other Name", time: 1000.002)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: "com.example.app"), "Other Name")
  }

  func testIconRevisionsDoNotReloadCachedDisplayNames() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let plist = root.appendingPathComponent("Contents/Info.plist")
    func writeInfo(icon: String) throws {
      try PropertyListSerialization.data(
        fromPropertyList: [
          "CFBundleIdentifier": "com.example.app", "CFBundlePackageType": "APPL",
          "CFBundleIconFile": icon, "CFBundleDisplayName": "Fixture Name",
        ], format: .xml, options: 0
      ).write(to: plist)
    }
    // Icon fixture bytes are used only for metadata and are never decoded as images.
    try Data([0]).write(to: directory.appendingPathComponent("First.icns"))
    let assets = directory.appendingPathComponent("Assets.car")
    try Data([2]).write(to: assets)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: assets.path)
    let other = directory.appendingPathComponent("Other.icns")
    try Data([1]).write(to: other)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: other.path)
    try writeInfo(icon: "First.icns")
    let bundle = try XCTUnwrap(Bundle(url: root))
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "First.icns")
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    var dependencies = ApplicationResourcesDependencies.live(workspace: .shared)
    XCTAssertNotNil(dependencies.identity(identifier, root, "icon"))
    try writeInfo(icon: "Other.icns")
    let updated = try XCTUnwrap(dependencies.identity(identifier, root, "icon"))
    dependencies.runningDisplayName = { _ in nil }
    dependencies.installedApplicationURL = { _ in root }
    let loadDisplayName = dependencies.displayName
    var nameLoads = 0
    dependencies.displayName = { url in
      nameLoads += 1
      return loadDisplayName(url)
    }
    let resources = ApplicationResources(dependencies: dependencies)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier.value), "Fixture Name")
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1001)], ofItemAtPath: other.path)
    let changed = try XCTUnwrap(dependencies.identity(identifier, root, "icon"))
    XCTAssertNotEqual(updated.revision, changed.revision)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier.value), "Fixture Name")
    XCTAssertEqual(nameLoads, 1)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1001)], ofItemAtPath: assets.path)
    let assetChanged = try XCTUnwrap(dependencies.identity(identifier, root, "icon"))
    XCTAssertNotEqual(changed.revision, assetChanged.revision)
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier.value), "Fixture Name")
    XCTAssertEqual(nameLoads, 1)
  }

}
