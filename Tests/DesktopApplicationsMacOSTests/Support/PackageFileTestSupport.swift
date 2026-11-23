import Foundation
import XCTest

func packageFileText(relativePath: String) throws -> String {
  try String(
    contentsOf: packageRepositoryRoot().appendingPathComponent(relativePath),
    encoding: .utf8
  )
}

func packageSourceFilesText(relativeRoot: String) throws -> String {
  let sourcesURL = packageRepositoryRoot().appendingPathComponent(relativeRoot)
  let fileURLs =
    FileManager.default
    .enumerator(at: sourcesURL, includingPropertiesForKeys: nil)?
    .compactMap { $0 as? URL }
    .filter { $0.pathExtension == "swift" } ?? []

  XCTAssertFalse(fileURLs.isEmpty, "\(relativeRoot) should contain source files.")
  return try fileURLs.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
}

func packageRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
