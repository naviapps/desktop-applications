import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

final class ApplicationBundleDisplayNameTests: XCTestCase {
  func testExplicitCopiesSharingIdentifierKeepTheirOwnNamesAndFallbacks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for (index, info, expected) in [
      (0, ["CFBundleDisplayName": "Chosen Copy", "CFBundleName": "Bundle Name"], "Chosen Copy"),
      (1, ["CFBundleDisplayName": "", "CFBundleName": "Bundle Name"], "Bundle Name"),
      (2, ["CFBundleDisplayName": "", "CFBundleName": ""], "Copy2"),
      (3, ["CFBundleDisplayName": " \n", "CFBundleName": "  Bundle 名  "], "  Bundle 名  "),
      (4, ["CFBundleDisplayName": "\t ", "CFBundleName": "\n "], "Copy4"),
    ] {
      let url = root.appendingPathComponent("Copy\(index).app")
      try FileManager.default.createDirectory(
        at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
      var info = info
      info["CFBundleIdentifier"] = "com.example.same"
      info["CFBundlePackageType"] = "APPL"
      let data = try PropertyListSerialization.data(
        fromPropertyList: info, format: .xml, options: 0)
      try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
      let bundle = try XCTUnwrap(Bundle(url: url))
      XCTAssertEqual(
        ApplicationBundleDisplayName.displayName(for: bundle, applicationURL: url), expected)
      XCTAssertEqual(
        ApplicationBundleDisplayName.freshDisplayName(for: bundle, applicationURL: url), expected)
    }
  }
  func testMetadataReaderIgnoresOversizedPropertyLists() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let info: [String: Any] = [
      "CFBundleDisplayName": "Oversized", "padding": Data(count: 4 * 1024 * 1024),
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
      .write(to: url)
    XCTAssertTrue(ApplicationBundleMetadata.dictionary(url).isEmpty)
  }

  @MainActor
  func testLocalizedSelectedCopyIsIndependentOfCompetingRunningMetadata() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: url) }
    let identifier = "com.example.same"
    let bundle = try makeLocalizedBundle(
      at: url, identifier: identifier, localizedDisplayName: "Selected Localized Copy")
    let resources = ApplicationResources(
      dependencies: ApplicationResourcesDependencies(
        runningDisplayName: { _ in "Running Copy" }, installedApplicationURL: { _ in url },
        displayName: { _ in "Registered Copy" }, icon: { _ in nil }, identity: { _, _, _ in nil }))
    XCTAssertEqual(resources.displayName(forBundleIdentifier: identifier), "Running Copy")
    XCTAssertEqual(
      ApplicationBundleDisplayName.displayName(for: bundle, applicationURL: url),
      "Selected Localized Copy")
    XCTAssertEqual(
      ApplicationBundleDisplayName.freshDisplayName(for: bundle, applicationURL: url),
      "Selected Localized Copy")
  }

  func testBlankLocalizedDisplayNameFallsBackToUnlocalizedDisplayName() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: url) }
    let bundle = try makeLocalizedBundle(
      at: url, identifier: "com.example.blank-localized", localizedDisplayName: " \n\t")
    XCTAssertEqual(
      bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String, " \n\t")
    XCTAssertEqual(
      ApplicationBundleDisplayName.displayName(for: bundle, applicationURL: url),
      "Unlocalized Copy")
    XCTAssertEqual(
      ApplicationBundleDisplayName.freshDisplayName(for: bundle, applicationURL: url),
      "Unlocalized Copy")
  }

  private func makeLocalizedBundle(
    at url: URL, identifier: String, localizedDisplayName: String
  ) throws -> Bundle {
    let localization = url.appendingPathComponent("Contents/Resources/en.lproj")
    try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
    let info = [
      "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL",
      "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "Unlocalized Copy",
      "CFBundleName": "Secondary Name",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: url.appendingPathComponent("Contents/Info.plist"))
    let localized = ["CFBundleDisplayName": localizedDisplayName]
    try PropertyListSerialization.data(fromPropertyList: localized, format: .xml, options: 0)
      .write(to: localization.appendingPathComponent("InfoPlist.strings"))
    return try XCTUnwrap(Bundle(url: url))
  }

}
