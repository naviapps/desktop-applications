# .NET shared contracts and Windows applications

`NaviApps.DesktopApplications` targets .NET 10. Shared identity, process validation,
lifecycle reconciliation and resource-cache transitions call the Rust native
library. `WindowsApplicationManager` and `WindowsApplicationResources` add native
Windows operations. Hosts own selection, permission UX, scheduling and UI.

## Install and load native assets

Obtain the `.nupkg` from one reviewed SDK build. The host package must carry an
asset matching the process runtime. macOS consumers use `osx-arm64` or `osx-x64`
for shared identity, reconciliation and resource caching. Windows consumers use
`win-x64` for shared contracts and native adapters. Use an x64 .NET process under
emulation on Windows 11 ARM64. Consumers can use the packaged asset directly after
restore.

With the package in a local feed, replace both placeholders and run from your
consumer project directory:

```sh
dotnet add package NaviApps.DesktopApplications \
  --version "<PACKAGE_VERSION>" --source /absolute/path/to/packages
```

The package carries the managed assembly, README and original notices. It places
the selected native libraries in `runtimes/<rid>/native/` as
`libdesktop_applications.dylib` on macOS or `desktop_applications.dll` on Windows.
Keep the runtime asset in the consumer output. Shared identity and cache calls
need native ABI 2. String inputs must be valid UTF-16. An unpaired surrogate
raises `ArgumentException` before the input reaches native code.

Native loading checks, in order:

1. `DESKTOP_APPLICATIONS_NATIVE_LIBRARY`, when set, explicitly selects a library.
2. `runtimes/<RuntimeInformation.RuntimeIdentifier>/native/` under
   `AppContext.BaseDirectory` supplies the packaged library when present.
3. Normal .NET native-library lookup resolves `desktop_applications.dll` on
   Windows or `libdesktop_applications.dylib` on macOS.

Use the environment override only for an explicitly selected matching library;
remove it when validating package delivery. An ABI mismatch throws
`InvalidOperationException`. Managed Windows operations throw
`PlatformNotSupportedException` on other platforms.

## Query applications

```csharp
using NaviApps.DesktopApplications;

var identifier = ApplicationIdentifier.Create(
    ApplicationIdentifierKind.Bundle, " com.example.app ");
Console.WriteLine(identifier.Value); // com.example.app

var manager = new WindowsApplicationManager();
foreach (var application in manager.GetRunningApplications())
    Console.WriteLine($"{application.Identity.ProcessId}: {application.DisplayName}");
```

Windows enumeration includes processes owning visible, unowned top-level windows.
Each sample reads a process once even if it owns several windows. Services,
background-only and inaccessible processes can be absent. Identifiers
are explicit absolute `.exe` paths; packaged-app/AUMID activation and installation
catalog discovery are outside this backend. `GetForegroundApplication()` identifies
the owning process, including where several logical applications share a host
process. After reading the metadata, it checks that the same process is still
running and owns the foreground. A mismatch at that check reports
`TargetChanged`. If there is no owner at the start, the query reports
`Unavailable`.

`GetApplication(processId)` obtains a fresh snapshot. `ActivateApplication(target)`
and `TerminateApplication(target, force: false)` revalidate recorded creation
metadata and identifiers before requesting an effect. Graceful termination queues
`WM_CLOSE` for the process's visible root windows; the app may refuse, prompt to
save or continue running. If metadata becomes unavailable between close requests
and the retained process handle confirms exit, the request ends successfully.
Activation and graceful termination check the selected
window's process and thread immediately before dispatch. A missing or changed owner
reports `TargetChanged`. A window may still change after the check. Foreground
activation follows OS policy. Catch
`ApplicationOperationException` and inspect `Code` and, for native failures,
`NativeCode`. No accepted request establishes eventual activation or termination.
`LaunchApplication` requires an explicit absolute `.exe` path and argument list;
it does not use a shell or search `PATH`.

## Observe sampled lifecycle changes

`ObserveAsync(interval, cancellationToken)` takes a baseline snapshot and emits
subsequent reconciled transitions. It does not replay already running applications
as initial launch events. The interval must be between 50 milliseconds and one
day, inclusive. Transitions entirely between samples can be missed. Cancellation
stops observation and does not terminate another application.

```csharp
using NaviApps.DesktopApplications;

static async Task ObserveApplications(CancellationToken cancellationToken)
{
    var manager = new WindowsApplicationManager();
    await foreach (var item in manager.ObserveAsync(
        TimeSpan.FromMilliseconds(250), cancellationToken))
        Console.WriteLine($"{item.Lifecycle}: {item.Application.Identity.ProcessId}");
}
```

The host owns the observing task and its cancellation. A cancelled observation
can throw `OperationCanceledException`; handle that at the task boundary.

Pass a collection of lifecycle kinds as the first argument to
`ObserveAsync(lifecycles, interval, cancellationToken)` to select which
transitions to receive. An empty collection completes without reading a sample.
`LaunchEventsAsync`, `TerminationEventsAsync`, `ActivationEventsAsync` and
`DeactivationEventsAsync` each yield only application snapshots.

`WaitForApplicationEventAsync` waits for the first future event with the given
lifecycle and identifier. The four `WaitForApplication…Async` convenience
methods return that event's application snapshot. Use the identifier from a
discovered application when its exact spelling matters. Identifier matching
compares the recorded namespace and spelling, and ignores events whose
identifier is unavailable. Several processes may share an identifier. Check the
returned process identity when the effect concerns one instance.

Start the wait before requesting the effect. The optional timeout includes the
baseline sample and can elapse before the first scheduled poll. An elapsed
deadline, cancellation or an invalid identifier returns null. The same
sampling limits apply to both observation and waits.

Custom polling adapters can pass two complete samples to
`ApplicationState.Reconcile(current)`. Use the returned state as the next
baseline. Samples and reconciliation results capture immutable copies of their
application or event lists. Equality compares values in their recorded order.
Snapshot equality also distinguishes display names with different Unicode
spellings. A display-name change alone does not emit a lifecycle transition.
Rust rejects duplicate process IDs, unavailable creation tokens and
frontmost identities absent from the application's sample.

## Display names and icons

.NET `WindowsApplicationResources` matches the backend's explicit absolute `.exe`
identity. It reads `FileVersionInfo.FileDescription` with an executable-name
fallback and obtains native Shell icons through
[SHGetFileInfoW](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetfileinfow).
`GetIcon` returns an independently owned `WindowsApplicationIcon` (`HICON`),
which the caller disposes; invalidation and SDK disposal release only cached
handles. There is no portable image encoding or macOS image conversion.
Windows resource calls are synchronous and Windows-only. Hosts choose scheduling
and call `Invalidate` after resource/theme changes not reflected in file size or
creation/write times. Packaged/AUMID icon discovery remains outside this backend.

```csharp
using NaviApps.DesktopApplications;

static void ReadResources(string selectedExecutable)
{
    using var resources = new WindowsApplicationResources();
    Console.WriteLine(resources.GetDisplayName(selectedExecutable));
    using var icon = resources.GetIcon(selectedExecutable);
    // Use the independently owned native icon before disposing it.
}
```

`selectedExecutable` must be an absolute `.exe` path chosen by the host.
The generic `ApplicationResourceCache<T>` has a different ownership contract:
returned managed values are borrowed. Serialize their use with invalidation and
disposal. A loader transfers owned values to the cache; superseded `IDisposable`
results and evicted owners are released outside the cache lock. Every retired
owner is released even if an `IDisposable.Dispose` call throws. A retired owner
cannot be inserted back into the same cache.

## Contributor validation

See [development and validation](../../README.md#development-and-validation) for pinned tools and
portable checks. On macOS, `mise exec -- make test-dotnet` tests the managed
contracts, packages both macOS runtime assets from the verified universal
framework, and runs a consumer for the executing architecture. The accepted
package is written to `.native-build/packages/`.

Use native ARM64 Python, Rust and MSVC on an owned Windows 11 ARM64 worker. Install
the `x86_64-pc-windows-msvc` Rust standard library and the x64 .NET SDK pinned in
`mise.toml`. Set `DOTNET_BIN` to the x64 executable's absolute path. Run the
Windows x64 gate from this checkout.

```powershell
python -B tools/windows.py
```

The gate builds Rust and C ABI tests, runs managed contracts with an owned x64
WinForms child, and installs the `win-x64` NuGet package in a clean consumer. The
package and receipt go to the configured artifact directory or `.native-build/`.
When the artifact directory is configured, `sdk-windows/win-x64` carries the
complete verified Windows build for later packing.

GitHub-hosted Windows CI uses an x64 runner to exercise native tests and the
installed package consumer.

To make one package with all three assets on macOS, place the accepted Windows
artifact directory and its native receipt from the same source build under
`.native-build/windows/win-x64/`.

```sh
mise exec -- python3 -B tools/nuget.py --include-windows
```

This verifies the Windows DLL and macOS framework against their respective
receipts and runs the packaged macOS consumer. Use a local feed or private
distribution. Choose one build for a given package ID and version.
