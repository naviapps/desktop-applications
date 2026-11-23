import Darwin
import Foundation

/// Reads the explicitly supplied bundle, without resolving another installed or running copy.
public enum ApplicationBundleDisplayName {
  public static func displayName(for bundle: Bundle, applicationURL: URL) -> String {
    resolve(applicationURL: applicationURL) { key in
      usableName(bundle.object(forInfoDictionaryKey: key) as? String)
        ?? usableName(bundle.infoDictionary?[key] as? String)
    }
  }

  // Foundation caches Bundle metadata. Cached installation resources must read updated bytes.
  static func freshDisplayName(for bundle: Bundle, applicationURL: URL) -> String {
    let info = ApplicationBundleMetadata.dictionary(
      ApplicationBundleMetadata.infoPlistURL(for: applicationURL))
    let localized = ApplicationBundleMetadata.dictionary(
      bundle.url(forResource: "InfoPlist", withExtension: "strings"))
    return resolve(applicationURL: applicationURL) { key in
      usableName(localized[key] as? String) ?? usableName(info[key] as? String)
    }
  }

  static func usableName(_ name: String?) -> String? {
    guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return name
  }

  private static func resolve(applicationURL: URL, value: (String) -> String?) -> String {
    for key in ["CFBundleDisplayName", "CFBundleName"] {
      if let name = value(key) { return name }
    }
    return applicationURL.deletingPathExtension().lastPathComponent
  }
}

enum ApplicationBundleMetadata {
  static func infoPlistURL(
    for applicationURL: URL,
    fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
  ) -> URL {
    let contents = applicationURL.appendingPathComponent("Contents", isDirectory: true)
    // Foundation gives the macOS-specific file precedence in this bundle layout.
    let platformPlist = contents.appendingPathComponent("Info-macos.plist")
    return fileExists(platformPlist) ? platformPlist : contents.appendingPathComponent("Info.plist")
  }

  private static let maximumMetadataBytes = 4 * 1024 * 1024

  static func dictionary(_ url: URL?) -> [String: Any] {
    guard let url, let data = try? readMetadata(at: url),
      let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
    else { return [:] }
    return value as? [String: Any] ?? [:]
  }

  private static func readMetadata(at url: URL) throws -> Data? {
    guard url.isFileURL else { return nil }
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return nil }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_size <= maximumMetadataBytes
    else { return nil }
    var data = Data()
    while data.count <= maximumMetadataBytes {
      let remaining = maximumMetadataBytes - data.count + 1
      guard let chunk = try file.read(upToCount: min(remaining, 64 * 1024)), !chunk.isEmpty else {
        return data
      }
      data.append(chunk)
    }
    return nil
  }
}
