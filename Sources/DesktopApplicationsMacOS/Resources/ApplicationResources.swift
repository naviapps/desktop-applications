import AppKit
import DesktopApplications

/// Native display names and icons. Hosts own selection, ordering and fallback UI.
@MainActor
public final class ApplicationResources {
  public static let shared = ApplicationResources()

  private enum Resource {
    case displayName(String)
    case icon(NSImage)
  }
  private var cache = ApplicationResourceCache<Resource>()
  private let dependencies: ApplicationResourcesDependencies
  private var observations: [(NotificationCenter, NSObjectProtocol)] = []

  public convenience init(workspace: NSWorkspace = .shared) {
    self.init(
      dependencies: .live(workspace: workspace),
      workspaceNotificationCenter: workspace.notificationCenter,
      localeNotificationCenter: .default)
  }

  init(
    dependencies: ApplicationResourcesDependencies,
    workspaceNotificationCenter: NotificationCenter? = nil,
    localeNotificationCenter: NotificationCenter? = nil
  ) {
    self.dependencies = dependencies
    if let center = workspaceNotificationCenter {
      for name in [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
      ] {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] note in
          let identifier =
            (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .bundleIdentifier
          MainActor.assumeIsolated { self?.invalidate(bundleIdentifier: identifier) }
        }
        observations.append((center, observer))
      }
    }
    if let center = localeNotificationCenter {
      let observer = center.addObserver(
        forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.invalidate() }
      }
      observations.append((center, observer))
    }
  }

  isolated deinit {
    for (center, observer) in observations { center.removeObserver(observer) }
  }

  /// Reads the first nonblank name from matching running applications,
  /// then the current registered installation.
  public func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
    guard let identifier = try? ApplicationIdentifier(kind: .bundle, value: bundleIdentifier) else {
      return nil
    }
    let runningName = dependencies.runningDisplayName(identifier.value)
    if let name = ApplicationBundleDisplayName.usableName(runningName) { return name }
    let resource = resource(for: identifier, variant: "displayName") { url in
      dependencies.displayName(url).map(Resource.displayName)
    }
    guard case .displayName(let name) = resource else { return nil }
    return name
  }

  /// Returns an installation's native icon, or nil. Missing lookups are never cached.
  public func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
    guard let identifier = try? ApplicationIdentifier(kind: .bundle, value: bundleIdentifier) else {
      return nil
    }
    let appearance = NSApp?.effectiveAppearance.name.rawValue ?? "default"
    let resource = resource(for: identifier, variant: "icon:" + appearance) { url in
      dependencies.icon(url).map(Resource.icon)
    }
    guard case .icon(let icon) = resource else { return nil }
    return icon
  }

  /// Clears every copy and variant of an identifier, or the entire cache.
  /// An invalid identifier leaves cached resources intact.
  /// Call after external resource edits that do not alter observed file metadata.
  public func invalidate(bundleIdentifier: String? = nil) {
    let identifier = bundleIdentifier.map {
      ApplicationIdentifier(recordedKind: .bundle, value: $0)
    }
    do {
      try cache.invalidate(identifier: identifier)
    } catch {
      // Only an explicit global invalidation can replace the cache wholesale.
      if identifier == nil { cache = ApplicationResourceCache() }
    }
  }

  private func resource(
    for identifier: ApplicationIdentifier, variant: String, load: (URL) -> Resource?
  ) -> Resource? {
    guard let url = dependencies.installedApplicationURL(identifier.value) else {
      invalidate(bundleIdentifier: identifier.value)
      return nil
    }
    var detectedReplacement = false
    func loadRegisteredResource() -> Resource? {
      if let current = dependencies.installedBundleIdentifier(url), current != identifier.value {
        detectedReplacement = true
        return nil
      }
      return load(url)
    }
    defer {
      if detectedReplacement { invalidate(bundleIdentifier: identifier.value) }
    }

    let variant =
      variant + ":" + Locale.current.identifier + ":"
      + Locale.preferredLanguages.joined(separator: ",")
    guard let identity = dependencies.identity(identifier, url, variant) else {
      invalidate(bundleIdentifier: identifier.value)
      return loadRegisteredResource()
    }
    do { return try cache.value(for: identity, load: loadRegisteredResource) } catch {
      return loadRegisteredResource()
    }
  }
}

@MainActor
struct ApplicationResourcesDependencies {
  var runningDisplayName: (String) -> String?
  var installedApplicationURL: (String) -> URL?
  var displayName: (URL) -> String?
  var icon: (URL) -> NSImage?
  var identity: (ApplicationIdentifier, URL, String) -> ApplicationResourceIdentity?
  var installedBundleIdentifier: (URL) -> String? = { _ in nil }

  static func live(workspace: NSWorkspace) -> Self {
    let manager = ApplicationManager(workspace: workspace)
    return Self(
      runningDisplayName: { manager.runningDisplayName(bundleIdentifier: $0) },
      installedApplicationURL: { manager.installedApplicationURL(bundleIdentifier: $0) },
      displayName: { url in
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let bundle = Bundle(url: url) else {
          return url.deletingPathExtension().lastPathComponent
        }
        return ApplicationBundleDisplayName.freshDisplayName(for: bundle, applicationURL: url)
      },
      icon: { url in
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return workspace.icon(forFile: url.path)
      },
      identity: nativeIdentity,
      installedBundleIdentifier: ApplicationBundleIdentifierInput.installedIdentifier(at:)
    )
  }

  private static func nativeIdentity(
    identifier: ApplicationIdentifier, url: URL, variant: String
  ) -> ApplicationResourceIdentity? {
    guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
    let resources = url.appendingPathComponent("Contents/Resources")
    let plist = ApplicationBundleMetadata.infoPlistURL(for: url)
    var paths = [url, plist, resources]
    // Display names need plist metadata; only icon identity needs its declarations.
    if !variant.hasPrefix("displayName:") {
      paths.append(resources.appendingPathComponent("Assets.car"))
      let info = ApplicationBundleMetadata.dictionary(plist)
      if let icon = info["CFBundleIconFile"] as? String, !icon.isEmpty {
        let name = (icon as NSString).pathExtension.isEmpty ? icon + ".icns" : icon
        paths.append(resources.appendingPathComponent(name))
      }
    }
    let localizations =
      (try? FileManager.default.contentsOfDirectory(
        at: resources, includingPropertiesForKeys: nil)) ?? []
    for localization in localizations.filter({ $0.pathExtension == "lproj" }).sorted(by: {
      $0.path < $1.path
    }) {
      paths.append(localization.appendingPathComponent("InfoPlist.strings"))
    }
    let revision = paths.map { path -> String in
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path) else {
        return "missing"
      }
      let file = [.systemNumber, .systemFileNumber, .size]
        .map { String(describing: attributes[$0]) }.joined(separator: ":")
      let times = [FileAttributeKey.modificationDate, .creationDate].map {
        (attributes[$0] as? Date).map { String($0.timeIntervalSinceReferenceDate.bitPattern) }
          ?? "missing"
      }.joined(separator: ":")
      return file + ":" + times
    }.joined(separator: "|")
    return ApplicationResourceIdentity(
      identifier: identifier, location: url.standardizedFileURL.path, revision: revision,
      variant: variant)
  }
}
