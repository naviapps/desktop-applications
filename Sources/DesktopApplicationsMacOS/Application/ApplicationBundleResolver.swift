import Foundation

struct ApplicationBundleResolver: Sendable {
  private let searchDirectories: [String]

  init(searchDirectories: [String]) {
    self.searchDirectories = searchDirectories
  }

  func urlForApplication(named name: String) -> URL? {
    guard isPlainApplicationName(name) else { return nil }

    let fileName = applicationBundleFileName(for: name)
    // Foundation's native URL conversion can discard a trailing NUL.
    for directory in searchDirectories where !directory.utf8.contains(0) {
      let expanded = (directory as NSString).expandingTildeInPath
      let url = URL(fileURLWithPath: expanded).appendingPathComponent(fileName)
      if isApplicationBundle(at: url) {
        return url
      }
    }
    return nil
  }

  private func isPlainApplicationName(_ name: String) -> Bool {
    !name.isEmpty && !name.hasPrefix("~") && !name.contains("/") && !name.utf8.contains(0)
  }

  private func applicationBundleFileName(for name: String) -> String {
    let url = URL(fileURLWithPath: name)
    guard url.pathExtension.lowercased() != "app" else {
      return name
    }
    return "\(name).app"
  }

  private func isApplicationBundle(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return url.pathExtension.lowercased() == "app"
      && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}
