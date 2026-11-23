using System.Runtime.CompilerServices;
using NaviApps.DesktopApplications;

static class ResourceCacheReentrancyTests
{
    private sealed class Resource(Action? onDispose = null) : IDisposable
    {
        public int DisposeCount { get; private set; }
        public void Dispose() { DisposeCount++; onDispose?.Invoke(); }
    }
    private static void Require(bool value, string message) { if (!value) throw new System.Diagnostics.UnreachableException(message); }
    internal static void Run(ApplicationIdentifier identifier)
    {
        var identity = new ApplicationResourceIdentity(identifier, "/selected.app", "1", "icon");
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var stale = new Resource();
            Require(cache.Get(identity, () => { cache.Invalidate(); return stale; }) is null,
                "Invalidation during loading returned a stale resource.");
            Require(stale.DisposeCount == 1, "Rejected native resource was not released exactly once.");
            var fresh = new Resource();
            Require(cache.Get(identity, () => { cache.Invalidate(); cache.Get(identity, () => fresh); return stale = new Resource(); }) is null,
                "Reentrant replacement accepted an older load.");
            Require(stale.DisposeCount == 1 && fresh.DisposeCount == 0, "Replacement resource ownership changed.");
            Require(ReferenceEquals(cache.Get(identity, () => throw new System.Diagnostics.UnreachableException("Replacement lost.")), fresh),
                "A stale completion overwrote the replacement.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var value = new Resource();
            Require(cache.Get(identity, () => { cache.Dispose(); return value; }) is null,
                "A disposed cache accepted an in-flight resource.");
            Require(value.DisposeCount == 1, "Dispose during load leaked a native resource.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var value = new Resource();
            Require(cache.Get(identity, () =>
            {
                var mutation = Task.Run(() => cache.Invalidate());
                Require(mutation.Wait(TimeSpan.FromSeconds(3)), "Loader executed while holding the cache lock.");
                return value;
            }) is null, "Concurrent invalidation accepted an obsolete resource.");
            Require(value.DisposeCount == 1, "Concurrent invalidation leaked the loaded resource.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var first = new Resource(() => throw new InvalidOperationException("Fixture disposal error."));
            var second = new Resource();
            cache.Get(identity, () => first);
            cache.Get(identity with { Location = "/other.app" }, () => second);
            try { cache.Invalidate(); throw new System.Diagnostics.UnreachableException("Disposal error lost."); }
            catch (InvalidOperationException) { }
            Require(first.DisposeCount == 1 && second.DisposeCount == 1,
                "One failed release prevented other native resources from being released.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var value = new Resource();
            cache.Get(identity, () => value);
            Parallel.For(0, 64, _ => Require(ReferenceEquals(cache.Get(identity,
                () => throw new System.Diagnostics.UnreachableException("Concurrent ready hit reloaded.")), value),
                "Ready cache readers superseded one another."));
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var shared = new Resource();
            cache.Get(identity, () => shared);
            var other = ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, "com.example.other");
            cache.Get(identity with { Identifier = other, Location = "/alias.app" }, () => shared);
            cache.Invalidate(identifier);
            Require(shared.DisposeCount == 0, "Selective invalidation released a still-owned alias.");
            cache.Invalidate(other);
            Require(shared.DisposeCount == 1, "Aliased native resource was released more than once.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var later = new Resource();
            var reentrantIdentity = identity with { Location = "/reentrant.app" };
            Resource? admitted = null;
            var first = new Resource(() => admitted = cache.Get(reentrantIdentity, () => later));
            cache.Get(identity, () => first);
            cache.Get(identity with { Location = "/later.app" }, () => later);
            cache.Invalidate();
            Require(admitted is null && later.DisposeCount == 1,
                "A disposal callback admitted another retired owner or released it twice.");
            var replacement = new Resource();
            Require(ReferenceEquals(cache.Get(reentrantIdentity, () => replacement), replacement),
                "Rejecting a retiring owner left a false ready cache entry.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var shared = new Resource();
            cache.Get(identity, () => shared);
            Require(cache.Get(identity with { Location = "/other.app" }, () =>
            {
                cache.Dispose();
                return shared;
            }) is null && shared.DisposeCount == 1,
                "Disposal during an in-flight alias load released the same owner twice.");
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var retired = RetireResource(cache, identity);
            GC.Collect();
            Require(!retired.TryGetTarget(out _), "The cache kept a retired owner alive.");
            GC.KeepAlive(cache);
        }
        using (var cache = new ApplicationResourceCache<Resource>())
        {
            var first = new Resource(() => cache.Invalidate());
            var second = new Resource();
            cache.Get(identity, () => first);
            cache.Get(identity with { Location = "/other.app" }, () => second);
            try { cache.Dispose(); throw new System.Diagnostics.UnreachableException("Reentrant disposal error lost."); }
            catch (ObjectDisposedException) { }
            Require(first.DisposeCount == 1 && second.DisposeCount == 1,
                "Reentrant disposal prevented other owners from being released.");
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference<Resource> RetireResource(ApplicationResourceCache<Resource> cache,
        ApplicationResourceIdentity identity)
    {
        var value = new Resource();
        cache.Get(identity, () => value);
        cache.Invalidate();
        Require(value.DisposeCount == 1, "Retired owner was not released.");
        return new WeakReference<Resource>(value);
    }
}
