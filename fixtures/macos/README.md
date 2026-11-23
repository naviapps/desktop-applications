# Owned macOS application acceptance

Run OS acceptance only in an owned isolated macOS GUI guest. Verify the minimum
supported runtime, macOS 26, separately from newer runtimes. The Host uses
the existing windowed Target app staged by `tools/macos.py`, with a unique bundle
identifier and a temporary work root. It does not change permissions or settings.

Prepare the pinned tools using [development and validation](../../README.md#development-and-validation)
and select full Xcode through `DEVELOPER_DIR` if needed. From the repository root,
the deterministic state test runs without launching an application:

```sh
mise exec -- swift test \
  --filter ApplicationManagerOpeningCancellationTests/testCancellationBeforeBeginSkipsDispatchAndResumesOnceDespiteLateCallbacks \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Build both native fixture executables without launching them:

```sh
mise exec -- swift build \
  --package-path fixtures/macos \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The cancellation observer uses `@testable import` to wrap the existing live
opening dependency. Keep the default debug configuration, which enables
testability. Every observed callback comes from the live AppKit adapter; the
observer forwards it immediately without synthesizing or delaying callbacks.

In the owned guest, select the native cancellation case:

```sh
DESKTOP_APPLICATIONS_ACCEPTANCE_CASE=opening-cancellation \
  mise exec -- python3 -B tools/macos.py
```

Omit the case environment variable to run both cancellation and
lifecycle acceptance. No VM or provider command is part of this fixture.

The cancellation case cancels its own Swift task at the live adapter's dispatch
boundary, after the SDK has installed its continuation and cancellation handler.
It then dispatches the actual AppKit request and forwards its real callback
immediately. `CancellationError` must win within two seconds, and the later real
callback must leave that result unchanged. A second instance must complete from
its own callback and receipt; both receipts identify distinct owned processes.
No target startup gate or assumption about AppKit callback timing is involved.
Deterministic unit tests separately cover late and duplicate callbacks, subsequent
request recovery, and cancellation/completion races. This native case does not
force the first callback to arrive while the second request is pending.

Success prints `Native macOS cancellation before a real late AppKit callback and
independent next launch passed.` Cleanup waits for dispatched callbacks, terminates
only processes matching the unique bundle identifier and staged bundle path, and
removes the cancellation data root. Each Target exits if its Host dies or its
bounded lifetime expires. The existing Python runner removes the staged app and
outer temporary work root.

## Lifecycle acceptance

The default run also opens the owned Target in accepting and refusing modes,
records launch and termination notifications, rejects a deliberately stale
creation token, and requests activation. It verifies graceful termination in
accepting mode, continued execution after a graceful refusal, then forced
termination of the owned process. Foreground activation is subject to OS policy;
the fixture does not claim that its activation request made the Target frontmost.

These native checks are separate from the deterministic Swift tests and package
consumption checks in [development and validation](../../README.md#development-and-validation).
