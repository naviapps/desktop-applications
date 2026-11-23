# ``DesktopApplications``

Shared application identity, process validation and lifecycle reconciliation backed by Rust.

A lookup identifier describes an application in an OS namespace. A process identity
adds an opaque creation token so a reused PID cannot authorize a recorded request.
A snapshot contains recorded metadata; adapters must obtain fresh OS state before
requesting an effect. Values are meaningful on their source machine and platform.
Native identity validation is not atomic with the OS effect; adapters must still
retain and revalidate their native resources.

Create a lookup identifier through the initializer to apply Rust's normalization
and validation. Bundle identifiers trim surrounding Unicode whitespace; executable
and app-user-model lookup keys preserve their spelling. Equality uses that exact
spelling and keeps distinct Unicode representations separate. Initialization does
not discover an installed application.

```swift
import DesktopApplications

let identifier = try ApplicationIdentifier(kind: .bundle, value: " com.example.app ")
// identifier.value is "com.example.app".
```

`ApplicationSnapshot` initializers record caller-supplied metadata without an OS
lookup. Snapshot equality compares display names by exact Unicode spelling,
including where two spellings render identically. A display-name change alone
does not emit a lifecycle transition. Use the macOS adapter to obtain native
snapshots. A zero creation token cannot authorize snapshot control. Merely
declaring an `.appUserModel` identifier does not add packaged-app activation to
the Windows adapter.

## Topics

### Identity and snapshots

- ``ApplicationIdentifier``
- ``ApplicationProcessIdentity``
- ``ApplicationSnapshot``
- ``ApplicationTargetValidationError``

### Native resource cache identity

- ``ApplicationResourceIdentity``
- ``ApplicationResourceCache``

The Rust cache keeps at most 128 installation/revision/variant identities in
recency order. Resource keys compare each field by exact spelling. Adapters
retain native values; missing values are retried. These resource identities never
authorize recorded process operations.

Rust owns the native cache and admits loaded values using monotonic generation
tokens. Invalidation, revision changes or a newer pending load discard stale
completions. Ready hits and unrelated loads preserve their current values.
Bindings retain only native objects, apply eviction deltas before releasing them,
and never transfer images or handles into Rust. Reentrant invalidation cannot
restore an obsolete value. The cache is synchronous and executor-confined in Swift;
Swift object release happens after the retained-value map has been updated.

### Lifecycle and request results

Polling adapters supply two complete application samples to
``ApplicationState/reconcile(_:)`` to derive ordered lifecycle changes. Use the
returned state as the baseline for the next sample. To start observing without
reporting already running applications as launches, capture a baseline before
the first interval. A sample with duplicate process IDs, unavailable creation
tokens or a frontmost identity absent from its application list is rejected.

- ``ApplicationState``
- ``ApplicationReconciliation``
- ``ApplicationEvent``
- ``ApplicationRequestResult``
- ``ApplicationOperationError``
- ``ApplicationLaunchError``
- ``ApplicationTerminationMode``
- ``DesktopApplicationsError``
