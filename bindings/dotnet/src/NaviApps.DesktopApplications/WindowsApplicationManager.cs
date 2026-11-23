using System.Runtime.CompilerServices;
using System.Text.Json;

namespace NaviApps.DesktopApplications;

public enum ApplicationOperationErrorCode { InvalidInput, Unavailable, TargetChanged, RequestRejected, NativeFailure }

public sealed class ApplicationOperationException : Exception
{
    public ApplicationOperationErrorCode Code { get; }
    public uint? NativeCode { get; }
    internal ApplicationOperationException(JsonElement failure) : base(failure.ToString())
    {
        if (failure.ValueKind == JsonValueKind.String)
        {
            Code = failure.GetString() switch
            {
                "invalidInput" => ApplicationOperationErrorCode.InvalidInput,
                "unavailable" => ApplicationOperationErrorCode.Unavailable,
                "targetChanged" => ApplicationOperationErrorCode.TargetChanged,
                "requestRejected" => ApplicationOperationErrorCode.RequestRejected,
                _ => throw new InvalidOperationException("Unknown native application failure.")
            };
        }
        else
        {
            Code = ApplicationOperationErrorCode.NativeFailure;
            NativeCode = failure.GetProperty("native").GetUInt32();
        }
    }
}

/// <summary>Native Windows app operations; callers own permission and selection policy.</summary>
public sealed class WindowsApplicationManager
{
    private static readonly EmptyRequest Empty = new();
    private readonly Func<ApplicationState> sample;
    private readonly TimeProvider clock;

    public WindowsApplicationManager() : this(() => Native.Decode<ApplicationState>(Call(16, Empty))) { }

    internal WindowsApplicationManager(Func<ApplicationState> sample, TimeProvider? clock = null)
    {
        this.sample = sample;
        this.clock = clock ?? TimeProvider.System;
    }

    private static JsonElement Call<T>(uint operation, T input)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows application management requires Windows.");
        var value = Native.Call(operation, input);
        if (value.TryGetProperty("failure", out var error)) throw new ApplicationOperationException(error);
        return value.GetProperty("result");
    }
#pragma warning disable CA1822 // Instance operations preserve the public native-adapter contract.
    public IReadOnlyList<ApplicationSnapshot> GetRunningApplications() => Native.Decode<ApplicationSnapshot[]>(Call(10, Empty));
    public ApplicationSnapshot GetForegroundApplication() => Native.Decode<ApplicationSnapshot>(Call(11, Empty));
    public ApplicationSnapshot GetApplication(uint processId) => Native.Decode<ApplicationSnapshot>(Call(12, new ProcessRequest(processId)));
    public uint LaunchApplication(string executable, IReadOnlyList<string>? arguments = null) =>
        Native.Decode<uint>(Call(13, new LaunchRequest(executable, arguments ?? Array.Empty<string>())));
    public void ActivateApplication(ApplicationSnapshot target) => Call(14, new ControlRequest(target, false));
    public void TerminateApplication(ApplicationSnapshot target, bool force = false) => Call(15, new ControlRequest(target, force));

    /// <summary>Samples visible desktop applications; transitions between samples may be missed.
    /// Cancellation stops observation and never terminates another application.</summary>
    public IAsyncEnumerable<ApplicationEvent> ObserveAsync(
        TimeSpan interval, CancellationToken cancellationToken = default) =>
        ObserveCoreAsync(interval, null, null, null, cancellationToken);

    /// <summary>Observes only the selected lifecycle kinds. An empty selection does not sample applications.</summary>
    public IAsyncEnumerable<ApplicationEvent> ObserveAsync(
        IEnumerable<ApplicationLifecycle> lifecycles, TimeSpan interval, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(lifecycles);
        var selected = lifecycles.ToArray();
        if (selected.Any(kind => !Enum.IsDefined(kind))) throw new ArgumentOutOfRangeException(nameof(lifecycles));
        return ObserveCoreAsync(interval, selected, null, null, cancellationToken);
    }

    public IAsyncEnumerable<ApplicationSnapshot> LaunchEventsAsync(
        TimeSpan interval, CancellationToken cancellationToken = default) =>
        ObserveSnapshotsAsync(ApplicationLifecycle.Launched, interval, cancellationToken);

    public IAsyncEnumerable<ApplicationSnapshot> TerminationEventsAsync(
        TimeSpan interval, CancellationToken cancellationToken = default) =>
        ObserveSnapshotsAsync(ApplicationLifecycle.Terminated, interval, cancellationToken);

    public IAsyncEnumerable<ApplicationSnapshot> ActivationEventsAsync(
        TimeSpan interval, CancellationToken cancellationToken = default) =>
        ObserveSnapshotsAsync(ApplicationLifecycle.Activated, interval, cancellationToken);

    public IAsyncEnumerable<ApplicationSnapshot> DeactivationEventsAsync(
        TimeSpan interval, CancellationToken cancellationToken = default) =>
        ObserveSnapshotsAsync(ApplicationLifecycle.Deactivated, interval, cancellationToken);

    /// <summary>Waits for a future sampled event. An elapsed deadline, invalid identifier or cancellation returns null.</summary>
    public async Task<ApplicationEvent?> WaitForApplicationEventAsync(
        ApplicationLifecycle lifecycle, ApplicationIdentifier identifier, TimeSpan interval,
        TimeSpan? timeout = null, CancellationToken cancellationToken = default)
    {
        if (cancellationToken.IsCancellationRequested || timeout <= TimeSpan.Zero) return null;
        ObservationDeadline? deadline = timeout is { } limit ? new(clock, clock.GetTimestamp(), limit) : null;
        ArgumentNullException.ThrowIfNull(identifier);
        if (!Enum.IsDefined(lifecycle)) throw new ArgumentOutOfRangeException(nameof(lifecycle));
        try { identifier = ApplicationIdentifier.Create(identifier.Kind, identifier.Value); }
        catch (ArgumentException) { return null; }
        try
        {
            await foreach (var item in ObserveCoreAsync(interval, [lifecycle], identifier, deadline, cancellationToken).ConfigureAwait(false))
                return cancellationToken.IsCancellationRequested || deadline?.HasElapsed == true ? null : item;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        return null;
    }

    public Task<ApplicationSnapshot?> WaitForApplicationLaunchAsync(
        ApplicationIdentifier identifier, TimeSpan interval, TimeSpan? timeout = null, CancellationToken cancellationToken = default) =>
        WaitForSnapshotAsync(ApplicationLifecycle.Launched, identifier, interval, timeout, cancellationToken);

    public Task<ApplicationSnapshot?> WaitForApplicationTerminationAsync(
        ApplicationIdentifier identifier, TimeSpan interval, TimeSpan? timeout = null, CancellationToken cancellationToken = default) =>
        WaitForSnapshotAsync(ApplicationLifecycle.Terminated, identifier, interval, timeout, cancellationToken);

    public Task<ApplicationSnapshot?> WaitForApplicationActivationAsync(
        ApplicationIdentifier identifier, TimeSpan interval, TimeSpan? timeout = null, CancellationToken cancellationToken = default) =>
        WaitForSnapshotAsync(ApplicationLifecycle.Activated, identifier, interval, timeout, cancellationToken);

    public Task<ApplicationSnapshot?> WaitForApplicationDeactivationAsync(
        ApplicationIdentifier identifier, TimeSpan interval, TimeSpan? timeout = null, CancellationToken cancellationToken = default) =>
        WaitForSnapshotAsync(ApplicationLifecycle.Deactivated, identifier, interval, timeout, cancellationToken);

    private async Task<ApplicationSnapshot?> WaitForSnapshotAsync(
        ApplicationLifecycle lifecycle, ApplicationIdentifier identifier, TimeSpan interval,
        TimeSpan? timeout, CancellationToken cancellationToken) =>
        (await WaitForApplicationEventAsync(lifecycle, identifier, interval, timeout, cancellationToken).ConfigureAwait(false))?.Application;

    private async IAsyncEnumerable<ApplicationSnapshot> ObserveSnapshotsAsync(
        ApplicationLifecycle lifecycle, TimeSpan interval, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var item in ObserveAsync([lifecycle], interval, cancellationToken).ConfigureAwait(false))
            yield return item.Application;
    }

    private readonly record struct ObservationDeadline(TimeProvider Clock, long Started, TimeSpan Timeout)
    {
        internal TimeSpan Remaining => Timeout - Clock.GetElapsedTime(Started);
        internal bool HasElapsed => Remaining <= TimeSpan.Zero;
    }

    private async IAsyncEnumerable<ApplicationEvent> ObserveCoreAsync(
        TimeSpan interval, ApplicationLifecycle[]? lifecycles, ApplicationIdentifier? identifier,
        ObservationDeadline? deadline, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (interval < TimeSpan.FromMilliseconds(50) || interval > TimeSpan.FromDays(1)) throw new ArgumentOutOfRangeException(nameof(interval));
        if (lifecycles is { Length: 0 } || deadline?.HasElapsed == true) yield break;
        cancellationToken.ThrowIfCancellationRequested();
        var previous = sample();
        using var timer = new PeriodicTimer(interval);
        while (true)
        {
            if (deadline is { } limit)
            {
                var remaining = limit.Remaining;
                if (remaining <= TimeSpan.Zero) yield break;
                if (remaining < timer.Period)
                    timer.Period = remaining < TimeSpan.FromMilliseconds(1) ? TimeSpan.FromMilliseconds(1) : remaining;
            }
            if (!await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false) || deadline?.HasElapsed == true)
                yield break;
            var current = sample();
            cancellationToken.ThrowIfCancellationRequested();
            if (deadline?.HasElapsed == true) yield break;
            var result = previous.Reconcile(current);
            previous = result.State;
            foreach (var item in SelectEvents(result.Events, lifecycles, identifier))
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (deadline?.HasElapsed == true) yield break;
                yield return item;
            }
        }
    }

    private static IEnumerable<ApplicationEvent> SelectEvents(
        IReadOnlyList<ApplicationEvent> events, ApplicationLifecycle[]? lifecycles, ApplicationIdentifier? identifier)
    {
        if (lifecycles is null || events.Count == 0) return events;
        var indices = Native.Decode<int[]>(Native.Call(4, new EventSelection(
            lifecycles,
            identifier,
            events.Select(item => new EventIdentity(item.Lifecycle, item.Application.Identifier)))));
        return indices.Select(index => events[index]);
    }
#pragma warning restore CA1822
}
