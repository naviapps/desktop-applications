[assembly: DoNotParallelize]

namespace NaviApps.DesktopApplications.Tests;

[TestClass]
public sealed class ApplicationValueTests
{
    private const string MalformedExecutable = "C:\\Apps\\\uD800.exe";
    private static readonly ApplicationIdentifier Identifier = new(ApplicationIdentifierKind.Bundle, "com.Example.App");
    private static readonly ApplicationSnapshot Snapshot = new(new(40, 100), Identifier, "Caf\u00e9", false);

    [TestMethod]
    public void BundleIdentifierNormalizesWhitespace() =>
        Assert.AreEqual(Identifier, ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, " com.Example.App\n"));

    [TestMethod]
    public void ExecutableIdentifierRejectsMalformedUtf16AndPreservesValidPairs()
    {
        Assert.Throws<ArgumentException>(() => ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, MalformedExecutable));
        const string executable = "C:\\Apps\\\U0001F680.exe";
        Assert.AreEqual(executable, ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, executable).Value);
    }

    [TestMethod]
    public void ExecutableAndResourceEqualityPreservesDistinctUnicodeSpellings()
    {
        const string composed = "caf\u00e9.app";
        const string decomposed = "cafe\u0301.app";
        var first = ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, composed);
        var second = ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, decomposed);
        Assert.AreEqual(composed, first.Value);
        Assert.AreEqual(decomposed, second.Value);
        Assert.AreEqual(2, new[] { first, second }.Distinct().Count());
        var resource = new ApplicationResourceIdentity(first, composed, composed, composed);
        var variants = new[]
        {
            resource,
            resource with { Location = decomposed },
            resource with { Revision = decomposed },
            resource with { Variant = decomposed },
        };
        Assert.AreEqual(variants.Length, variants.Distinct().Count());
    }

    [TestMethod]
    public void SnapshotAndEventEqualityPreserveDistinctDisplayNameSpellings()
    {
        var decomposed = Snapshot with { DisplayName = "Cafe\u0301" };
        Assert.AreEqual(2, new[] { Snapshot, decomposed }.Distinct().Count());
        Assert.IsTrue(
            new ApplicationEvent(ApplicationLifecycle.Activated, Snapshot)
            != new ApplicationEvent(ApplicationLifecycle.Activated, decomposed));
    }

    [TestMethod]
    public void TargetValidationRejectsReusedPidAndMalformedIdentity()
    {
        Assert.IsNull(Snapshot.ValidateAgainst(Snapshot));
        var reused = Snapshot with { Identity = Snapshot.Identity with { StartTime = 101 } };
        Assert.AreEqual(ApplicationTargetValidationError.TargetChanged, Snapshot.ValidateAgainst(reused));
        var literalReplacement = Snapshot with
        {
            Identifier = new(ApplicationIdentifierKind.Executable, "C:\\Apps\\\uFFFD.exe"),
        };
        var malformed = Snapshot with { Identifier = new(ApplicationIdentifierKind.Executable, MalformedExecutable) };
        Assert.IsNull(literalReplacement.ValidateAgainst(literalReplacement));
        Assert.Throws<ArgumentException>(() => malformed.ValidateAgainst(literalReplacement));
    }

    [TestMethod]
    public void ReconciliationCapturesImmutableStateAndOrderedEvents()
    {
        var reused = Snapshot with { Identity = Snapshot.Identity with { StartTime = 101 }, DisplayName = "Cafe\u0301" };
        var previousApplications = new List<ApplicationSnapshot> { Snapshot };
        var previous = new ApplicationState(previousApplications, Snapshot.Identity);
        var nextApplications = new[] { reused };
        var next = new ApplicationState(nextApplications, reused.Identity);
        previousApplications[0] = reused;
        nextApplications[0] = Snapshot;
        Assert.IsTrue(Snapshot == previous.Applications[0]);
        Assert.IsTrue(reused == next.Applications[0]);
        var delta = previous.Reconcile(next);
        Assert.IsTrue(next == delta.State);
        Assert.AreEqual(next.GetHashCode(), delta.State.GetHashCode());
        Assert.AreEqual(Snapshot with { Terminated = true },
            delta.Events.Single(e => e.Lifecycle == ApplicationLifecycle.Terminated).Application);
        var copiedEvents = delta.Events.ToList();
        var copiedDelta = delta with { Events = copiedEvents };
        var copyOfNext = next with { Applications = new List<ApplicationSnapshot> { reused } };
        Assert.IsTrue(next == copyOfNext);
        Assert.AreEqual(next.GetHashCode(), copyOfNext.GetHashCode());
        copiedEvents.Reverse();
        Assert.IsTrue(delta == copiedDelta);
        Assert.AreEqual(delta.GetHashCode(), copiedDelta.GetHashCode());
        Assert.IsTrue(delta != delta with { Events = copiedEvents });
        Assert.IsTrue(next != next with { Frontmost = null });
        if (delta.State.Applications is IList<ApplicationSnapshot> applications)
            Assert.Throws<NotSupportedException>(() => applications[0] = Snapshot);
        if (delta.Events is IList<ApplicationEvent> events)
            Assert.Throws<NotSupportedException>(() => events.Clear());
    }

    [TestMethod]
    public void ReconciliationPreservesTypedNativeRejection()
    {
        var sample = new ApplicationState([Snapshot with { Identity = Snapshot.Identity with { StartTime = 0 } }], null);
        var error = Assert.Throws<ArgumentException>(() => ApplicationState.Empty.Reconcile(sample));
        Assert.AreEqual("IdentityUnavailable", error.Message);
    }
}
