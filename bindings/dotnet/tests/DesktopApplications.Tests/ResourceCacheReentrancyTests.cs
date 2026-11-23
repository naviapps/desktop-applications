using System.Runtime.CompilerServices;

namespace NaviApps.DesktopApplications.Tests;

[TestClass]
public sealed class ResourceCacheReentrancyTests
{
    private sealed class Resource(Action? onDispose = null) : IDisposable
    {
        public int DisposeCount { get; private set; }
        public void Dispose() { DisposeCount++; onDispose?.Invoke(); }
    }
    private static readonly ApplicationResourceIdentity Identity = new(
        new(ApplicationIdentifierKind.Bundle, "com.Example.App"), "/selected.app", "1", "icon");

    [TestMethod]
    public void InvalidationDuringLoadRejectsStaleResourcesAndPreservesReplacement()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var stale = new Resource();
        Assert.IsTrue(cache.Get(Identity, () => { cache.Invalidate(); return stale; }) is null,
            "Invalidation during loading returned a stale resource.");
        Assert.IsTrue(stale.DisposeCount == 1, "Rejected native resource was not released exactly once.");
        var fresh = new Resource();
        Assert.IsTrue(cache.Get(Identity, () => { cache.Invalidate(); cache.Get(Identity, () => fresh); return stale = new Resource(); }) is null,
            "Reentrant replacement accepted an older load.");
        Assert.IsTrue(stale.DisposeCount == 1 && fresh.DisposeCount == 0, "Replacement resource ownership changed.");
        Assert.IsTrue(ReferenceEquals(cache.Get(Identity, () => throw new AssertFailedException("Replacement lost.")), fresh),
            "A stale completion overwrote the replacement.");
    }

    [TestMethod]
    public void DisposalDuringLoadReleasesUnacceptedResources()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var value = new Resource();
        Assert.IsTrue(cache.Get(Identity, () => { cache.Dispose(); return value; }) is null,
            "A disposed cache accepted an in-flight resource.");
        Assert.IsTrue(value.DisposeCount == 1, "Dispose during load leaked a native resource.");
    }

    [TestMethod]
    public void LoaderDoesNotHoldLockDuringConcurrentInvalidation()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var value = new Resource();
        Assert.IsTrue(cache.Get(Identity, () =>
        {
            var mutation = Task.Run(() => cache.Invalidate());
            Assert.IsTrue(mutation.Wait(TimeSpan.FromSeconds(3)), "Loader executed while holding the cache lock.");
            return value;
        }) is null, "Concurrent invalidation accepted an obsolete resource.");
        Assert.IsTrue(value.DisposeCount == 1, "Concurrent invalidation leaked the loaded resource.");
    }

    [TestMethod]
    public void InvalidationReleasesOtherOwnersWhenOneDisposalFails()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var first = new Resource(() => throw new InvalidOperationException("Fixture disposal error."));
        var second = new Resource();
        cache.Get(Identity, () => first);
        cache.Get(Identity with { Location = "/other.app" }, () => second);
        Assert.ThrowsExactly<InvalidOperationException>(() => cache.Invalidate());
        Assert.IsTrue(first.DisposeCount == 1 && second.DisposeCount == 1,
            "One failed release prevented other native resources from being released.");
    }

    [TestMethod]
    public void ConcurrentReadyReadersKeepTheSameResource()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var value = new Resource();
        cache.Get(Identity, () => value);
        Parallel.For(0, 64, _ => Assert.IsTrue(ReferenceEquals(cache.Get(Identity,
            () => throw new AssertFailedException("Concurrent ready hit reloaded.")), value),
            "Ready cache readers superseded one another."));
    }

    [TestMethod]
    public void InvalidatingOneAliasKeepsResourceUntilLastOwnerIsRemoved()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var shared = new Resource();
        cache.Get(Identity, () => shared);
        var other = ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, "com.example.other");
        cache.Get(Identity with { Identifier = other, Location = "/alias.app" }, () => shared);
        cache.Invalidate(Identity.Identifier);
        Assert.IsTrue(shared.DisposeCount == 0, "Selective invalidation released a still-owned alias.");
        cache.Invalidate(other);
        Assert.IsTrue(shared.DisposeCount == 1, "Aliased native resource was released more than once.");
    }

    [TestMethod]
    public void DisposalCallbackCannotReadAnotherRetiringOwner()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var later = new Resource();
        var reentrantIdentity = Identity with { Location = "/reentrant.app" };
        Resource? admitted = null;
        var first = new Resource(() => admitted = cache.Get(reentrantIdentity, () => later));
        cache.Get(Identity, () => first);
        cache.Get(Identity with { Location = "/later.app" }, () => later);
        cache.Invalidate();
        Assert.IsTrue(admitted is null && later.DisposeCount == 1,
            "A disposal callback admitted another retired owner or released it twice.");
        var replacement = new Resource();
        Assert.IsTrue(ReferenceEquals(cache.Get(reentrantIdentity, () => replacement), replacement),
            "Rejecting a retiring owner left a false ready cache entry.");
    }

    [TestMethod]
    public void DisposalDuringAliasLoadReleasesSharedOwnerOnce()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var shared = new Resource();
        cache.Get(Identity, () => shared);
        Assert.IsTrue(cache.Get(Identity with { Location = "/other.app" }, () =>
        {
            cache.Dispose();
            return shared;
        }) is null && shared.DisposeCount == 1,
            "Disposal during an in-flight alias load released the same owner twice.");
    }

    [TestMethod]
    public void CacheDoesNotKeepRetiredResourcesAlive()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var retired = RetireResource(cache, Identity);
        GC.Collect();
        Assert.IsTrue(!retired.TryGetTarget(out _), "The cache kept a retired owner alive.");
        GC.KeepAlive(cache);
    }

    [TestMethod]
    public void ReentrantDisposalStillReleasesOtherOwners()
    {
        using var cache = new ApplicationResourceCache<Resource>();
        var first = new Resource(() => cache.Invalidate());
        var second = new Resource();
        cache.Get(Identity, () => first);
        cache.Get(Identity with { Location = "/other.app" }, () => second);
        Assert.ThrowsExactly<ObjectDisposedException>(() => cache.Dispose());
        Assert.IsTrue(first.DisposeCount == 1 && second.DisposeCount == 1,
            "Reentrant disposal prevented other owners from being released.");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference<Resource> RetireResource(ApplicationResourceCache<Resource> cache,
        ApplicationResourceIdentity identity)
    {
        var value = new Resource();
        cache.Get(identity, () => value);
        cache.Invalidate();
        Assert.AreEqual(1, value.DisposeCount, "Retired owner was not released.");
        return new WeakReference<Resource>(value);
    }
}
