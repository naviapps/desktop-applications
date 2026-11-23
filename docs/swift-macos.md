# Swift application discovery and lifecycle on macOS

AppKit application discovery, launch, control and lifecycle notifications.

The manager is main-actor isolated and owns native application resources. Hosts
choose application filtering, permission UX, persistence and product behavior. Window geometry and placement are
provided by WindowManagement; URLs, folders and action plans belong to DesktopActions.

Snapshot control rechecks creation metadata and the recorded identifier. For PID
control with an expected bundle identifier, surrounding whitespace is trimmed from
the expected value and the remaining spelling must match the running application
exactly. Accepted requests do not guarantee foreground activation, termination or
saved documents.

Opening by bundle identifier rechecks a standard macOS bundle's current
identifier before dispatch, ignoring ASCII letter case. It reads
`Contents/Info-macos.plist` if present, otherwise `Contents/Info.plist`, from a
regular file up to 4 MiB. A readable, different identifier returns
`installedApplicationNotFound`. If metadata cannot be verified in this layout,
the usual bundle validation still applies. Opening by file URL validates the
caller-selected installation without checking its identifier. The identifier
check and the OS launch request are separate operations.

Lifecycle streams register notification observers synchronously before returning.
Use `events()` for all lifecycle notifications or `events(lifecycles:)` to
observe just the requested kinds in one stream. An empty set ends immediately
without registering observers. The single-kind streams (`launchEvents()`,
`terminationEvents()`, `activationEvents()` and `deactivationEvents()`) yield
application snapshots. Notifications received after subscription buffer until
consumed; notifications from before subscription are not replayed. Cancel the
consuming task to end observation and remove the stream's observers.

Configured application opening uses `try await` and throws `CancellationError`
when cancellation wins completion. An already cancelled task skips lookup,
validation and dispatch. Cancellation after dispatch ends the wait promptly;
AppKit may still complete the launch. The first callback or cancellation wins,
and subsequent callbacks are ignored. Do not infer that cancellation rejected the
launch or automatically retry it. Validation and OS rejection remain typed
`ApplicationRequestResult` failures; no implicit timeout is imposed.

The host selects the application URL before making the request.

```swift
import AppKit
import DesktopApplications
import DesktopApplicationsMacOS

@MainActor
func openSelectedApplication(_ applicationURL: URL) async throws(CancellationError)
  -> ApplicationRequestResult<ApplicationLaunchError>
{
  try await ApplicationManager().openApplication(
    at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
}
```

Subscribe before requesting an effect when that effect's notification matters.
The `waitForApplication…` methods wait for a future matching notification; they
do not return a previously recorded event or query the current running state.
They return nil for cancellation, an invalid blank identifier, or an elapsed
optional timeout. The timeout starts before observer setup. A zero or negative
timeout and a previously cancelled task skip the subscription. The host chooses
its timeout and owns the observing task. Bundle identifiers retain Swift's
canonical Unicode equality after trimming the requested identifier. The stream
and wait return the snapshot exactly as it was recorded.

The duplicate activation coordinator is notification-based coordination, not an
exclusive ownership lock; the host decides whether another instance should exit.

## Native applications

The name-based installed application lookup searches the supplied directories in
order. A name containing U+0000 returns nil. Search directories containing
U+0000 are skipped before native path conversion.

## Display names and native icons

Swift `ApplicationResources` provides running/installed display-name lookup and
native `NSImage` icons. It skips empty or whitespace-only names from matching
running applications before falling back to the current registered installation.
`ApplicationBundleDisplayName.displayName(for:applicationURL:)`
reads the supplied bundle directly, even when another running or registered copy
shares its identifier. It looks for `CFBundleDisplayName`, then `CFBundleName`,
then falls back to the file name. For each metadata key, it uses the localized
name if present and nonblank, then tries the unlocalized value. Bundle
registration, selection, filtering, sorting and fallback UI symbols stay in the host.
If a registered installation disappears, installed resources return nil instead of
a file-name or generic file-icon fallback. When loading installed resources, a
readable bundle identifier that differs from the requested identifier also returns
nil. Running names still come from running metadata; reinstallation at the same
location is read afresh. The installed-resource cache reads property-list metadata
only from regular files up to 4 MiB per file; unavailable or oversized metadata
falls back to the remaining name sources.

The AppKit adapter resolves the registered URL on every lookup and samples bundle,
plist and localized-name file metadata. Installed resource lookup uses
`Contents/Info-macos.plist` when present and `Contents/Info.plist` otherwise.
Icon lookups also sample declared icon/asset metadata. The adapter observes
launch, termination and locale changes. Installed
names read fresh plist bytes on a cache miss because Foundation caches bundle
dictionaries. Call `invalidate(bundleIdentifier:)` after
external edits not reflected in that metadata; omit the identifier to clear all
resources. An invalid identifier leaves cached resources intact. Icon variants
include application appearance. Invalidating a cache does not force a host view
to redraw or flush the operating system's own caches.

The host supplies fallback UI and redraw policy; the SDK returns nil when no
native resource is available.
