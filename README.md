# DesktopApplications

Private application identity, discovery and lifecycle SDK for Rust, Swift, C and .NET.

Rust owns identifier normalization, recorded process validation, lifecycle
reconciliation and bounded resource-cache decisions. Native adapters own OS
application resources and effects. Hosts own application selection, product
policy, permission prompts, persistence and UI. Window control belongs to
[WindowManagement](https://github.com/naviapps/window-management); URL, file,
Shortcuts and action plans belong to
[DesktopActions](https://github.com/naviapps/desktop-actions).

## Documentation

| Need                                                     | Guide                                                                                                                                                                                          |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Swift shared values and cache API                        | [DesktopApplications DocC catalog](https://github.com/naviapps/desktop-applications/blob/main/Sources/DesktopApplications/DesktopApplications.docc/DesktopApplications.md)                     |
| AppKit discovery, opening and lifecycle API              | [DesktopApplicationsMacOS DocC catalog](https://github.com/naviapps/desktop-applications/blob/main/Sources/DesktopApplicationsMacOS/DesktopApplicationsMacOS.docc/DesktopApplicationsMacOS.md) |
| C result buffers and failures                            | [C ownership and failures](#c-ownership-and-failures)                                                                                                                                          |
| .NET installation and Windows usage                      | [.NET guide](https://github.com/naviapps/desktop-applications/blob/main/bindings/dotnet/README.md)                                                                                             |
| Contributor setup, checks, native artifacts and CI scope | [Development and validation](#development-and-validation)                                                                                                                                      |
| Owned macOS lifecycle and cancellation acceptance        | [macOS fixture guide](https://github.com/naviapps/desktop-applications/blob/main/fixtures/macos/README.md)                                                                                     |

## Install from Swift

Swift consumers pin `https://github.com/naviapps/desktop-applications.git` to a
full commit and select `DesktopApplications` or `DesktopApplicationsMacOS`.
The tracked native framework permits SwiftPM installation without Rust on the
consumer machine. Authenticated repository access is configured by the consumer;
no credential is stored in this package.

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
full revision when updating the SDK; package access remains consumer configured.

## Install from Rust or C

The public `desktop-applications` crate requires Rust 1.99 or later and the
target platform linker. It uses Serde and does not link the SDK's C framework
or build a native discovery adapter. Set up authenticated Git access in your
own environment and replace the placeholder with the full published commit:

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

The public [C header](https://github.com/naviapps/desktop-applications/blob/main/crates/ffi/include/desktop_applications.h) defines ABI 2.
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
before releasing objects whose destructors may reenter the adapter. See the
[C ABI fixture](https://github.com/naviapps/desktop-applications/blob/main/crates/ffi/tests/c/abi.c) and
[independent C client](https://github.com/naviapps/desktop-applications/blob/main/fixtures/c-consumer/main.c) for executable ownership examples.

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
[macOS API catalog](https://github.com/naviapps/desktop-applications/blob/main/Sources/DesktopApplicationsMacOS/DesktopApplicationsMacOS.docc/DesktopApplicationsMacOS.md)
explains opening, subscriptions and resource lookup.

## Install from .NET

Use `NaviApps.DesktopApplications` with ABI 2 native assets from the same SDK
build. The macOS packaging gate supplies `osx-arm64` and `osx-x64` assets for
shared operations. The Windows packaging gate supplies `win-x64` for shared
and native Windows operations. Windows 11 ARM64 runs the x64 .NET consumer under
emulation. Both gates run a clean local NuGet consumer. All managed
identity and cache operations need the native library. See the
[.NET guide](https://github.com/naviapps/desktop-applications/blob/main/bindings/dotnet/README.md)
for installation, native loading, Windows limitations and examples.

## Development and validation

Use full Xcode with Swift 6.3 or newer, macOS 26 or newer, Rust from
`rust-toolchain.toml`, and .NET 10. Select Xcode through `DEVELOPER_DIR` if needed.
From the SDK root, review `mise.toml`, trust that reviewed configuration, then
install the pinned tools and fetch dependencies before the validation:

```sh
mise trust mise.toml
mise install
mise exec -- cargo fetch --locked
mise exec -- cargo fetch --locked --manifest-path fixtures/windows/Cargo.toml
mise exec -- make check
```

`make check` runs lint, the Rust workspace and Windows fixture tests, the managed
.NET fixture, strict Swift tests, and a standalone SwiftPM consumer. These checks
use the SDK fixtures in this checkout and the public SDK Tooling revision pinned
in [`mise.toml`](mise.toml). Mise fetches that revision for lint, formatting,
Swift consumer, DocC, and installed-consumer checks.

Public GitHub Actions runs the same Swift tests and standalone consumer on macOS 26
with Xcode 26.6 and macOS 27 with Xcode 27.2. The public Windows x64 job runs the
Rust workspace tests and the .NET binding fixture against a DLL built from source.

### Focused checks and consumers

| Command from the repository root  | Evidence                                                   |
| --------------------------------- | ---------------------------------------------------------- |
| `mise run lint`                   | Owned-source formatting and semantic lint                  |
| `mise exec -- make test-rust`     | Rust workspace and Windows fixture tests                   |
| `mise exec -- make test-managed`  | Managed API contracts                                      |
| `mise exec -- make test-consumer` | Strict build and execution of the external SwiftPM fixture |

Use `mise run format` when intentionally formatting owned source. The quality
commands skip native artifacts and the original notices under `ThirdParty/`.

`test-consumer` copies the installable Swift package, tests, native artifacts and
notices into a temporary SDK tree, then builds and runs `fixtures/swift-consumer`
as a separate package. It imports both products and exercises synthetic
identifier normalization, caching and process validation without real OS effects.

### Distribution validation

The distribution recipe in [`sdk-distribution.toml`](sdk-distribution.toml) covers
native framework provenance, portable build-driver tests, DocC, and clean NuGet
and installed consumers. Local native and package checks require
`NAVI_SDK_TOOLING_SOURCE` to point to the absolute path of a clean SDK Tooling checkout
at the revision in [`mise.toml`](mise.toml) before running `make check-distribution`,
`make native-verify`, `make native`, or `make test-dotnet`.

Maintainers can run the macOS and Windows x64 distribution checks in SDK Tooling
for a reviewed SDK commit on `main`.

```sh
gh workflow run check-sdk-distribution.yml -R naviapps/sdk-tooling \
  -f sdk=desktop-applications -f revision="$(git rev-parse HEAD)"
```

To exercise the installed Rust and C clients locally, run the following from a
clean committed checkout on owned macOS:

```sh
mise exec -- make test-installed-consumers
```

The [Rust Git client](https://github.com/naviapps/desktop-applications/blob/main/fixtures/rust-consumer/src/main.rs)
resolves a fresh lock from the exact SDK commit through an owned local Git mirror.
Its independent Cargo cache may fetch registry crates separately from the workspace
fetch. The [C client](https://github.com/naviapps/desktop-applications/blob/main/fixtures/c-consumer/main.c)
compiles against a copy of the tracked framework and notices. Both exercise
synthetic normalization, stale-target rejection and cache invalidation without
discovering or controlling applications. A shallow checkout needs a complete local
mirror or bundle. Run `mise run sdk-tooling -- installed-consumers --git-source <path>`
to use that source.
The independent clients verify installation from a local source mirror and the
tracked framework bytes.

### Native acceptance

Use the [owned macOS fixture guide](https://github.com/naviapps/desktop-applications/blob/main/fixtures/macos/README.md)
for application lifecycle and opening-cancellation acceptance. Windows x64 runtime
checks can run on the existing owned isolated ARM64 worker. The
[.NET guide](https://github.com/naviapps/desktop-applications/blob/main/bindings/dotnet/README.md#contributor-validation)
describes its application-effects and package-consumption runner.

### Native artifacts and notices

Rebuild after native-input changes. Install the Rust standard-library targets
`aarch64-apple-darwin` and `x86_64-apple-darwin` for a universal rebuild. Set
`NAVI_SDK_TOOLING_SOURCE` as described under [distribution validation](#distribution-validation)
and run the rebuild.

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

Rust crates live in `crates/`, including the C ABI fixture in `crates/ffi/tests/c/`.
The Rust core integration tests own the shared identity and lifecycle case
matrix. Swift and .NET verify public value semantics, native data and error
decoding, resource ownership and adapter behavior.
Swift uses `Sources/` and `Tests/`; .NET uses `bindings/dotnet/src/` and
`bindings/dotnet/tests/`. Standalone native fixture apps live in `fixtures/macos/`
and `fixtures/windows/`, whose locked Cargo workspace supplies the x64 Windows
test target for the .NET acceptance driver.

## License

This project is available under the [MIT License](LICENSE). Third-party components
retain their original notices in [ThirdParty](ThirdParty).
