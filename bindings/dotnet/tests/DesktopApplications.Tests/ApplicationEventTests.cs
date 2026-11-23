using System.Diagnostics;
using NaviApps.DesktopApplications;

internal static class ApplicationEventTests
{
    private static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(50);
    private static readonly TimeSpan Budget = TimeSpan.FromSeconds(5);
    private static readonly ApplicationIdentifier Target = new(ApplicationIdentifierKind.Executable, @"C:\Owned\Fixture.exe");
    private static readonly ApplicationSnapshot First = new(new(42, 100), Target, "Fixture", false);

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new UnreachableException(message);
    }

    internal static async Task Run()
    {
        var inert = new WindowsApplicationManager(() => throw new UnreachableException("Unexpected sample."));
        await using (var empty = inert.ObserveAsync([], Interval).GetAsyncEnumerator())
            Require(!await empty.MoveNextAsync(), "An empty filter returned events.");
        var candidate = await inert.WaitForApplicationLaunchAsync(Target, Interval, TimeSpan.Zero);
        Require(candidate is null, "Expired wait sampled the application state.");
        using (var canceled = new CancellationTokenSource())
        {
            canceled.Cancel();
            candidate = await inert.WaitForApplicationLaunchAsync(Target, Interval, cancellationToken: canceled.Token);
            Require(candidate is null, "Pre-cancelled wait sampled the application state.");
        }
        candidate = await inert.WaitForApplicationLaunchAsync(Target with { Value = "" }, Interval);
        Require(candidate is null, "Invalid identifier reached the sample.");

        var reused = First with { Identity = First.Identity with { StartTime = 101 } };
        var previous = new ApplicationState([First], First.Identity);
        var current = new ApplicationState([reused], reused.Identity);
        var manager = Manager(previous, current);
        var kinds = new[] { ApplicationLifecycle.Terminated, ApplicationLifecycle.Activated };
        var observation = manager.ObserveAsync(kinds, Interval);
        Array.Fill(kinds, ApplicationLifecycle.Launched);
        using (var cancellation = new CancellationTokenSource(Budget))
        await using (var events = observation.GetAsyncEnumerator(cancellation.Token))
        {
            Require(await events.MoveNextAsync() && events.Current.Lifecycle == ApplicationLifecycle.Terminated
                && events.Current.Application == First with { Terminated = true },
                "Filtered observation lost the original termination.");
            Require(await events.MoveNextAsync() && events.Current.Lifecycle == ApplicationLifecycle.Activated
                && events.Current.Application == reused, "Filtered observation lost the replacement activation.");
        }

        var other = First with
        {
            Identity = new(43, 100),
            Identifier = Target with { Value = @"C:\Owned\Other.exe" }
        };
        manager = Manager(ApplicationState.Empty, new([other], null), new([other, First], null));
        candidate = await manager.WaitForApplicationLaunchAsync(Target, Interval, Budget);
        Require(candidate == First, "Wait did not skip an unrelated launch.");

        manager = Manager(previous, previous);
        candidate = await manager.WaitForApplicationLaunchAsync(Target, TimeSpan.FromDays(1), Interval)
            .WaitAsync(Budget);
        Require(candidate is null, "Wait replayed an existing application.");

        using var stopped = new CancellationTokenSource(Budget);
        var samples = 0;
        manager = new WindowsApplicationManager(() =>
        {
            if (samples++ == 0) return ApplicationState.Empty;
            stopped.Cancel();
            return previous;
        });
        candidate = await manager.WaitForApplicationLaunchAsync(Target, Interval, TimeSpan.MaxValue, stopped.Token);
        Require(candidate is null && samples == 2, "Cancellation during sampling lost to a matching event.");
    }

    private static WindowsApplicationManager Manager(params ApplicationState[] states)
    {
        var index = 0;
        return new WindowsApplicationManager(() => states[Math.Min(index++, states.Length - 1)]);
    }
}
