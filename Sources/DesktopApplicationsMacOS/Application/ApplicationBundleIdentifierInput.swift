import DesktopApplications
import Foundation

enum ApplicationBundleIdentifierInput {
  static func trimmedNonEmpty(_ value: String) -> String? {
    try? ApplicationIdentifier(kind: .bundle, value: value).value
  }

  // Read the current installation rather than Foundation's cached Bundle metadata.
  static func installedIdentifier(at applicationURL: URL) -> String? {
    identifier(inInfoPlistAt: ApplicationBundleMetadata.infoPlistURL(for: applicationURL))
  }

  static func identifier(inInfoPlistAt url: URL) -> String? {
    let info = ApplicationBundleMetadata.dictionary(url)
    return (info["CFBundleIdentifier"] as? String).flatMap(trimmedNonEmpty)
  }
}
