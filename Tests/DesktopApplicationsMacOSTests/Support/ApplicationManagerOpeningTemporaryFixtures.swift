import Foundation
import XCTest

func webURL(
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> URL {
  try XCTUnwrap(URL(string: "https://example.com"), file: file, line: line)
}

func missingURLScheme(
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> URL {
  try XCTUnwrap(URL(string: "invalid"), file: file, line: line)
}

func temporaryFileURL(pathExtension: String = "txt") throws -> URL {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("example-\(UUID().uuidString).\(pathExtension)")
  try Data().write(to: fileURL)
  return fileURL
}

func missingFileURL(pathExtension: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("missing-\(UUID().uuidString)")
    .appendingPathExtension(pathExtension)
}

func temporaryDirectoryURL(
  prefix: String,
  pathExtension: String? = nil
) -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
  guard let pathExtension else { return url }
  return url.appendingPathExtension(pathExtension)
}

enum TemporaryExecutableKind {
  case executableFile
  case nonExecutableFile
  case directory
  case missing
}

func temporaryApplicationBundleURL(
  packageType: String = "APPL",
  executableKind: TemporaryExecutableKind = .executableFile,
  bundleIdentifier: String? = "com.example.app",
  macOSBundleIdentifier: String? = nil
) throws -> URL {
  let applicationDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("example-\(UUID().uuidString).app")
  let contentsDirectory = applicationDirectory.appendingPathComponent("Contents")
  let executableDirectory = contentsDirectory.appendingPathComponent("MacOS")
  let executableURL = executableDirectory.appendingPathComponent("Example")
  try FileManager.default.createDirectory(
    at: executableDirectory,
    withIntermediateDirectories: true
  )
  var properties = ["CFBundleExecutable": "Example", "CFBundlePackageType": packageType]
  properties["CFBundleIdentifier"] = bundleIdentifier
  let infoPlist = try PropertyListSerialization.data(
    fromPropertyList: properties, format: .xml, options: 0)
  try infoPlist.write(to: contentsDirectory.appendingPathComponent("Info.plist"))
  if let macOSBundleIdentifier {
    properties["CFBundleIdentifier"] = macOSBundleIdentifier
    let platformPlist = try PropertyListSerialization.data(
      fromPropertyList: properties, format: .xml, options: 0)
    try platformPlist.write(to: contentsDirectory.appendingPathComponent("Info-macos.plist"))
  }
  switch executableKind {
  case .executableFile:
    try Data().write(to: executableURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executableURL.path
    )
  case .nonExecutableFile:
    try Data().write(to: executableURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: executableURL.path
    )
  case .directory:
    try FileManager.default.createDirectory(
      at: executableURL,
      withIntermediateDirectories: false
    )
  case .missing:
    break
  }
  return applicationDirectory
}

func removeTemporaryItem(at url: URL) {
  try? FileManager.default.removeItem(at: url)
}
