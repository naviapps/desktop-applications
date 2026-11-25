# DesktopApplications

Application identity, discovery and lifecycle SDK for Rust, Swift, C and .NET.

Rust owns identifier normalization, recorded process validation, lifecycle
reconciliation and bounded resource-cache decisions. Native adapters own OS
application resources and effects. Hosts own application selection, product
policy, permission prompts, persistence and UI. Window control belongs to
[WindowManagement](https://github.com/naviapps/window-management); URL, file,
Shortcuts and action plans belong to
[DesktopActions](https://github.com/naviapps/desktop-actions).

## Documentation

| Need                                                     | Guide                                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Swift shared values and cache API                        | [DesktopApplications guide](https://github.com/naviapps/desktop-applications/blob/main/docs/swift.md)            |
| AppKit discovery, opening and lifecycle API              | [DesktopApplicationsMacOS guide](https://github.com/naviapps/desktop-applications/blob/main/docs/swift-macos.md) |
| C result buffers and failures                            | [C ownership and failures](#c-ownership-and-failures)                                                            |
| .NET installation and Windows usage                      | [.NET guide](https://github.com/naviapps/desktop-applications/blob/main/bindings/dotnet/README.md)               |
| Contributor setup, checks, native artifacts and CI scope | [Development and validation](#development-and-validation)                                                        |
| Owned macOS lifecycle and cancellation acceptance        | [macOS fixture guide](fixtures/acceptance/macos/README.md)                                                       |

## Install from Swift

Swift consumers pin `https://github.com/naviapps/desktop-applications.git` to a
full commit and select `DesktopApplications` or `DesktopApplicationsMacOS`.
SwiftPM uses the tracked native framework without a Rust toolchain.

A minimal consumer `Package.swift` can select both public products. Replace
`<FULL_PUBLISHED_COMMIT_SHA>` with a reviewed full published revision containing
these products:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "ApplicationClient",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(
      url: "https://github.com/naviapps/desktop-applications.git",
      revision: "<FULL_PUBLISHED_COMMIT_SHA>")
  ],
  targets: [
    .executableTarget(
      name: "ApplicationClient",
      dependencies: [
        .product(name: "DesktopApplications", package: "desktop-applications"),
        .product(name: "DesktopApplicationsMacOS", package: "desktop-applications"),
      ])
  ]
)
```

The package has no Swift package dependencies. Supply the executable's source
under `Sources/ApplicationClient/`, then run `swift build`. Choose a newer accepted
full revision when updating the SDK.

## Install from Rust or C

The public `desktop-applications` crate requires Rust 1.99 or later and the
target platform linker. It uses Serde and does not link the SDK's C framework
or build a native discovery adapter. Replace the placeholder with a full
published commit:

```toml
[dependencies]
desktop-applications = { git = "https://github.com/naviapps/desktop-applications.git", rev = "<FULL_PUBLISHED_COMMIT_SHA>" }
```

For C on macOS 26 or later, install `CDesktopApplications.framework` from
`Artifacts/CDesktopApplications.xcframework/macos-arm64_x86_64`, preserving its
framework symlinks and retained notices. Include
`<CDesktopApplications/desktop_applications.h>` and use Clang from the macOS
developer tools. Set `framework_dir` to the absolute directory containing the
installed framework:

```sh
xcrun clang -std=c17 -mmacosx-version-min=26.0 consumer.c \
  -F "$framework_dir" -framework CDesktopApplications \
  -Xlinker -rpath -Xlinker "$framework_dir" -o consumer
```

Keep the header and binary from the same SDK revision. The C client consumes
that framework and does not need Rust or a source checkout.

## C ownership and failures

The generated [C header](https://github.com/naviapps/desktop-applications/blob/main/Artifacts/CDesktopApplications.xcframework/macos-arm64_x86_64/CDesktopApplications.framework/Versions/A/Headers/desktop_applications.h) defines ABI 2.
Keep headers, managed bindings and native binaries from one SDK build. Inputs
are UTF-8 JSON, at most 8 MiB, and must remain readable for their declared
lengths; a null/length check cannot establish arbitrary pointer validity.

`desktop_applications_query` returns an owned result buffer, or a null pointer
when no result owner can be returned. Null indicates rejected null or oversized
input, or a caught native panic. It is not a typed application rejection. A
nonnull result contains either a `value` or an `error` JSON property. Windows
operation results additionally carry a `result` or `failure` inside `value`, as used by the [.NET adapter](https://github.com/naviapps/desktop-applications/blob/main/bindings/dotnet/README.md).

`desktop_applications_buffer_data` borrows bytes from its result owner. Copy them
before calling `desktop_applications_buffer_free`, and free each nonnull owner
exactly once. Keep an independent resource-cache owner alive for all its queries;
destroy it only with exclusive ownership and no concurrent/live queries. Cache
transitions contain generations and eviction deltas; detach retained values
before releasing objects whose destructors may reenter the adapter. The
[C client](fixtures/consumers/c/main.c) exercises ownership on macOS and Windows.

## Swift usage

AppKit adapters are main-actor isolated. Read a fresh snapshot before selecting a
process operation; an accepted OS request does not guarantee its eventual effect.

```swift
import DesktopApplications
import DesktopApplicationsMacOS

@MainActor
func frontmostApplicationName() -> String? {
  ApplicationManager().frontmostApplication()?.displayName
}
```

Configured opening uses `try await` and throws `CancellationError` when
cancellation wins; a dispatched OS launch may still complete. Handle cancellation
separately from typed `ApplicationRequestResult` failures. The
[macOS API guide](https://github.com/naviapps/desktop-applications/blob/main/docs/swift-macos.md)
explains opening, subscriptions and resource lookup.

## Install from .NET

See the [NuGet guide](bindings/dotnet/README.md#install-and-load-native-assets)
for package installation and a portable first call. It also covers
[Windows applications](bindings/dotnet/README.md#query-windows-applications)
and the managed resource APIs.

## Development and validation

Use full Xcode with Swift 6.3 or newer, macOS 26 or newer, Rust from
`rust-toolchain.toml`, and .NET 10. Select Xcode through `DEVELOPER_DIR` if needed.
From the SDK root, review `mise.toml`, trust that reviewed configuration, then
install the pinned tools and fetch dependencies before the validation:

```sh
mise trust mise.toml
mise install
mise exec -- cargo fetch --locked
mise exec -- cargo fetch --locked --manifest-path fixtures/acceptance/windows/Cargo.toml
mise exec -- make check
```

`make check` runs lint, the Rust workspace and Windows fixture tests, managed
MSTest cases, strict Swift tests, and a standalone SwiftPM consumer. These checks
use the SDK fixtures in this checkout and the public SDK Tooling revision pinned
in [`mise.toml`](mise.toml). Mise fetches that revision for lint, formatting,
Swift consumer and installed-consumer checks.

Public GitHub Actions runs the same Swift tests and standalone consumer on macOS 26
with Xcode 26.6 and macOS 27 with Xcode 27.2. The public Windows x64 job runs the
Rust workspace tests and the .NET binding tests against a DLL built from source.

### Focused checks and consumers

| Command from the repository root  | Evidence                                                   |
| --------------------------------- | ---------------------------------------------------------- |
| `mise exec -- make lint`          | Owned-source formatting and semantic lint                  |
| `mise exec -- make test-rust`     | Rust workspace and Windows fixture tests                   |
| `mise exec -- make test-managed`  | Managed API contracts                                      |
| `mise exec -- make test-consumer` | Strict build and execution of the external SwiftPM fixture |

The .NET test project restores its pinned MSTest SDK from its test-only
NuGet configuration. The `DesktopApplicationsNativeLibrary` MSBuild property
copies a selected native library beside the managed output for source checks.
After `make test-managed`, rerun a named case from the built test project and
write a TRX report under its ignored output directory.

```sh
tests=bindings/dotnet/tests/DesktopApplications.Tests
mise exec -- dotnet run --no-build --configuration Release --project "$tests" -- \
  --filter 'FullyQualifiedName~BundleIdentifierNormalizesWhitespace' \
  --report-trx --results-directory "$PWD/$tests/obj/TestResults"
```

Use `mise exec -- make format` to format owned source. The quality
commands skip native artifacts and the original notices under `ThirdParty/`.

`test-consumer` copies the installable Swift package, tests, native artifacts and
notices into a temporary SDK tree, then builds and runs `fixtures/consumers/swift`
as a separate package. It imports both products and exercises synthetic
identifier normalization, caching and process validation without real OS effects.

### Distribution validation

The `[distribution]` section of [`sdk-tooling.toml`](sdk-tooling.toml) covers
native framework provenance, portable build-driver tests, clean NuGet and
installed consumers. Use `mise exec -- make check-distribution` on macOS
with the checkout's pinned tooling. The SDK-owned checks live in
[`distribution`](distribution).

Maintainers can run distribution checks in SDK Tooling for a reviewed commit on
`main`. The workflow combines the verified Windows x64 and macOS native assets
into a single NuGet package. Independent consumers restore and run the same
package on both macOS architectures and on Windows x64. Set
`windows-on-arm=true` to repeat the x64 check on Windows 11 ARM64.

```sh
gh workflow run check-sdk-distribution.yml -R naviapps/sdk-tooling \
  -f sdk=desktop-applications -f "revision=$(git rev-parse HEAD)"
```

To exercise the installed Rust and C clients locally, run the following from a
clean committed checkout on owned macOS:

```sh
mise exec -- make test-installed-consumers
```

The [Rust Git client](fixtures/consumers/rust/src/main.rs)
resolves a fresh lock from the exact SDK commit through an owned local Git mirror.
Its independent Cargo cache may fetch registry crates separately from the workspace
fetch. The [C client](fixtures/consumers/c/main.c)
compiles against a copy of the tracked framework and notices. Both exercise
synthetic normalization, stale-target rejection and cache invalidation without
discovering or controlling applications. A shallow checkout needs a complete local
mirror or bundle. Run `mise run sdk-tooling -- rust-c-consumers --git-source <path>`
to use that source.

### Local NuGet checks

On macOS, `mise exec -- make test-nuget` tests the managed contracts and runs an
independent consumer against a temporary package from the verified framework.
To pack all three runtimes locally, put the accepted Windows DLL and native
receipt for this source under `.native-build/windows/win-x64/`:

```sh
mise run sdk-tooling -- python -m distribution.pack_nuget \
  --runtime osx-arm64 --runtime osx-x64 --runtime win-x64
mise run sdk-tooling -- nuget-consumer \
  .native-build/packages/NaviApps.DesktopApplications.0.1.0.nupkg
```

The packer verifies both native receipts and writes the combined package and its
SHA-256 receipt together. The second command runs the packaged macOS consumer.

### Native acceptance

Use the [owned macOS fixture guide](fixtures/acceptance/macos/README.md)
for application lifecycle and opening-cancellation acceptance.

On an owned, isolated Windows 11 ARM64 worker, use native ARM64 Python, Rust
and MSVC. Install the `x86_64-pc-windows-msvc` Rust standard library and the
x64 .NET SDK pinned in [`global.json`](global.json). Set `DOTNET_BIN` to its
absolute path. With SDK Tooling at the revision pinned in `mise.toml`, run:

```powershell
$tooling = (Resolve-Path ../sdk-tooling).Path
python -I -B "$tooling/ci/run_sdk_tooling.py" python -m distribution.verify_windows
```

The gate builds Rust and C ABI tests, runs MSTest, exercises application
lifecycle with an owned x64 Win32 child, and verifies a clean `win-x64` NuGet
consumer. Add `--native-aot` to run the native executable with JSON reflection
disabled and check Shell resources for the fixture. The hosted distribution
workflow runs that check on Windows x64. With an artifact directory configured,
`sdk-windows/win-x64` receives the accepted Windows build and its receipt.

### Native artifacts and notices

Rebuild after native-input changes. The build regenerates the C header and
module map before packaging. Source checks compare the generated bytes with
the copies bundled in the XCFramework. Install the Rust standard-library targets
`aarch64-apple-darwin` and `x86_64-apple-darwin` for a universal rebuild.
The `[native]` section of [`sdk-tooling.toml`](sdk-tooling.toml) declares the native
framework policy.

```sh
mise exec -- make native
```

The builder verifies source inputs, locked dependency bytes and notices, exports,
deployment target and packaged output hashes. Preserve tracked artifacts and
`Artifacts/native-build.json` when distributing.

The framework retains verbatim notice bodies in `Resources/ThirdPartyNotices.txt`.
Original notices and Rust runtime provenance remain under `ThirdParty/`; NuGet
packages retain the original notice files. Local packaging does not publish to a feed.

### Repository layout

Rust crates live in `crates/`. Rust core integration tests own shared identity
and lifecycle behavior. Swift and .NET verify public value semantics, native data and error
decoding, resource ownership and adapter behavior.
Swift uses `Sources/` and `Tests/`; .NET uses `bindings/dotnet/src/` and
`bindings/dotnet/tests/`. Independent package consumers live in `fixtures/consumers/`.
The standalone native apps live in `fixtures/acceptance/`, where the Windows Cargo
workspace supplies the x64 test target for the .NET acceptance driver. The scripts
for building and checking release packages live in `distribution/`.

## License

This project is available under the [MIT License](LICENSE). Third-party components
retain their original notices in [ThirdParty](ThirdParty).
