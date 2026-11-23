namespace NaviApps.DesktopApplications.Tests;

[TestClass]
public sealed class ApplicationEventTests
{
    private static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(50);
    private static readonly TimeSpan Budget = TimeSpan.FromSeconds(5);
    private static readonly ApplicationIdentifier Target = new(ApplicationIdentifierKind.Executable, @"C:\Owned\Fixture.exe");
    private static readonly ApplicationSnapshot First = new(new(42, 100), Target, "Fixture", false);
    private static readonly ApplicationState Previous = new([First], First.Identity);

    [TestMethod]
    public async Task EmptyObservationFilterDoesNotSample()
    {
        var inert = new WindowsApplicationManager(() => throw new AssertFailedException("Unexpected sample."));
        await using var events = inert.ObserveAsync([], Interval).GetAsyncEnumerator();
        Assert.IsFalse(await events.MoveNextAsync());
    }

    [TestMethod]
    public async Task ExpiredCancelledAndInvalidLaunchWaitsDoNotSample()
    {
        var inert = new WindowsApplicationManager(() => throw new AssertFailedException("Unexpected sample."));
        Assert.IsNull(await inert.WaitForApplicationLaunchAsync(Target, Interval, TimeSpan.Zero));
        using var canceled = new CancellationTokenSource();
        canceled.Cancel();
        Assert.IsNull(await inert.WaitForApplicationLaunchAsync(Target, Interval, cancellationToken: canceled.Token));
        Assert.IsNull(await inert.WaitForApplicationLaunchAsync(Target with { Value = "" }, Interval));
    }

    [TestMethod]
    public async Task ObservationCopiesTheFilterAndReportsReplacementInOrder()
    {
        var reused = First with { Identity = First.Identity with { StartTime = 101 } };
        var manager = Manager(Previous, new([reused], reused.Identity));
        var kinds = new[] { ApplicationLifecycle.Terminated, ApplicationLifecycle.Activated };
        var observation = manager.ObserveAsync(kinds, Interval);
        Array.Fill(kinds, ApplicationLifecycle.Launched);
        using var cancellation = new CancellationTokenSource(Budget);
        await using var events = observation.GetAsyncEnumerator(cancellation.Token);
        Assert.IsTrue(await events.MoveNextAsync());
        Assert.AreEqual(ApplicationLifecycle.Terminated, events.Current.Lifecycle);
        Assert.AreEqual(First with { Terminated = true }, events.Current.Application);
        Assert.IsTrue(await events.MoveNextAsync());
        Assert.AreEqual(ApplicationLifecycle.Activated, events.Current.Lifecycle);
        Assert.AreEqual(reused, events.Current.Application);
    }

    [TestMethod]
    public async Task LaunchWaitSkipsUnrelatedApplication()
    {
        var other = First with
        {
            Identity = new(43, 100),
            Identifier = Target with { Value = @"C:\Owned\Other.exe" },
        };
        var manager = Manager(ApplicationState.Empty, new([other], null), new([other, First], null));
        Assert.AreEqual(First, await manager.WaitForApplicationLaunchAsync(Target, Interval, Budget));
    }

    [TestMethod]
    public async Task LaunchWaitDoesNotReplayAnExistingApplication()
    {
        var manager = Manager(Previous, Previous);
        Assert.IsNull(await manager.WaitForApplicationLaunchAsync(Target, TimeSpan.FromDays(1), Interval)
            .WaitAsync(Budget));
    }

    [TestMethod]
    public async Task CancellationDuringSamplingWinsOverTheMatchingEvent()
    {
        using var stopped = new CancellationTokenSource(Budget);
        var samples = 0;
        var manager = new WindowsApplicationManager(() =>
        {
            if (samples++ == 0) return ApplicationState.Empty;
            stopped.Cancel();
            return Previous;
        });
        Assert.IsNull(await manager.WaitForApplicationLaunchAsync(Target, Interval, TimeSpan.MaxValue, stopped.Token));
        Assert.AreEqual(2, samples);
    }

    private static WindowsApplicationManager Manager(params ApplicationState[] states)
    {
        var index = 0;
        return new WindowsApplicationManager(() => states[Math.Min(index++, states.Length - 1)]);
    }
}
