namespace NaviApps.DesktopApplications.Tests;

[TestClass]
public sealed class ResourceCacheTests
{
    private static readonly ApplicationResourceIdentity Identity = new(
        new(ApplicationIdentifierKind.Bundle, "com.Example.App"), "/selected.app", "1", "name:en");

    [TestMethod]
    public void CacheRejectsMalformedNativeKeysBeforeLoading()
    {
        using var cache = new ApplicationResourceCache<string>();
        Assert.Throws<ArgumentException>(() => cache.Get(Identity with { Location = "C:\\Apps\\\uD800.exe" },
            () => throw new AssertFailedException("Malformed cache key reached the loader.")));
    }

    [TestMethod]
    public void CacheRetriesMissesAndReloadsInvalidatedValues()
    {
        using var cache = new ApplicationResourceCache<string>();
        Assert.IsNull(cache.Get(Identity, () => null));
        Assert.AreEqual("Selected", cache.Get(Identity, () => "Selected"));
        Assert.AreEqual("Selected", cache.Get(Identity,
            () => throw new AssertFailedException("A retained hit called the loader.")));
        cache.Invalidate(Identity.Identifier);
        Assert.AreEqual("Reloaded", cache.Get(Identity, () => "Reloaded"));
    }

    [TestMethod]
    public void EvictionAndInvalidationReleaseOwnedResources()
    {
        using var cache = new ApplicationResourceCache<OwnedResource>();
        var evicted = new OwnedResource();
        cache.Get(Identity, () => evicted);
        for (int index = 1; index <= 128; index++)
            cache.Get(Identity with { Location = $"/{index}.app" }, () => new OwnedResource());
        Assert.IsTrue(evicted.Disposed);
        var invalidated = new OwnedResource();
        cache.Get(Identity, () => invalidated);
        cache.Invalidate(Identity.Identifier);
        Assert.IsTrue(invalidated.Disposed);
    }

    [TestMethod]
    public void DisposalReleasesRetainedResources()
    {
        var cache = new ApplicationResourceCache<OwnedResource>();
        var retained = new OwnedResource();
        using (cache) cache.Get(Identity, () => retained);
        Assert.IsTrue(retained.Disposed);
    }

    private sealed class OwnedResource : IDisposable
    {
        public bool Disposed { get; private set; }
        public void Dispose() => Disposed = true;
    }
}
