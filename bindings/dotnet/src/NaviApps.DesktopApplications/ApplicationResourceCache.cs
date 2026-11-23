using System.Runtime.CompilerServices;

namespace NaviApps.DesktopApplications;

/// <summary>Native installation/revision tokens, meaningful only on their source platform and machine.</summary>
public sealed record ApplicationResourceIdentity(ApplicationIdentifier Identifier, string Location, string Revision, string Variant);

/// <summary>Retains adapter values under Rust's bounded cache transitions. Returned values are borrowed;
/// callers serialize their use with invalidation/disposal. A loader transfers owned values to the cache.
/// Superseded loads return null and release unretained IDisposable values. A retired disposable
/// owner cannot be admitted again by this cache. Callbacks run outside the cache lock.</summary>
public sealed class ApplicationResourceCache<T> : IDisposable where T : class
{
    private sealed record Transition(ulong? Generation, IReadOnlyList<ulong> EvictedGenerations, bool LoadIsCurrent);
    private static readonly object RetirementMarker = new();
    private readonly object gate = new();
    private readonly ResourceCacheHandle owner = Native.CreateResourceCache();
    private readonly Dictionary<ulong, T> values = new();
    private readonly ConditionalWeakTable<T, object> retiredOwners = new();
    private bool disposed;

    public T? Get(ApplicationResourceIdentity identity, Func<T?> load)
    {
        ArgumentNullException.ThrowIfNull(identity);
        ArgumentNullException.ThrowIfNull(load);
        ulong generation;
        T? cached;
        IReadOnlyList<IDisposable> retired;
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var transition = Query(new { action = "resolve", resource = identity });
            generation = transition.Generation ?? throw new InvalidOperationException("Native load generation missing.");
            retired = Apply(transition);
            cached = values.GetValueOrDefault(generation);
        }
        Release(retired);
        lock (gate)
        {
            if (disposed || !CanRetain(generation)) return null;
            if (cached is not null) return cached;
        }
        var loaded = load();
        if (loaded is null) return null;
        bool retained;
        try
        {
            lock (gate)
            {
                retained = !disposed && !retiredOwners.TryGetValue(loaded, out _)
                    && Query(new { action = "admitLoad", generation }).LoadIsCurrent;
                if (retained) values[generation] = loaded;
                retired = retained ? Array.Empty<IDisposable>() : RetireUnowned([loaded]);
            }
        }
        catch (Exception error)
        {
            lock (gate)
                retired = RetireUnowned([loaded]);
            Release(retired, error);
            throw;
        }
        Release(retired);
        return retained ? loaded : null;
    }

    /// <summary>Invalidates every installation/variant of an identifier, or all resources.</summary>
    public void Invalidate(ApplicationIdentifier? identifier = null)
    {
        IReadOnlyList<IDisposable> retired;
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            retired = Apply(Query(new { action = "invalidate", identifier }));
        }
        Release(retired);
    }

    private Transition Query(object action) => Native.Decode<Transition>(Native.QueryResourceCache(owner, action));
    private bool CanRetain(ulong generation) => Query(new { action = "validateLoad", generation }).LoadIsCurrent;

    // Detach retired owners before callbacks so reentrant work sees coherent state.
    private IReadOnlyList<IDisposable> Apply(Transition transition)
    {
        if (transition.EvictedGenerations.Count == 0) return Array.Empty<IDisposable>();
        var removed = new List<T>();
        foreach (var generation in transition.EvictedGenerations)
            if (values.Remove(generation, out var value)) removed.Add(value);
        return RetireUnowned(removed);
    }

    private List<IDisposable> RetireUnowned(IEnumerable<T> removed)
    {
        // Record retirement before invoking any callbacks. The weak keys allow
        // aliases in live loads to be recognized without retaining released owners.
        var retired = new List<IDisposable>();
        foreach (var value in removed)
            if (value is IDisposable owned && !values.Values.Any(other => ReferenceEquals(value, other))
                && retiredOwners.TryAdd(value, RetirementMarker))
                retired.Add(owned);
        return retired;
    }

    private static void Release(IEnumerable<IDisposable> retired, Exception? failure = null)
    {
        List<Exception>? errors = failure is null ? null : new() { failure };
        foreach (var owned in retired)
            try { owned.Dispose(); }
            catch (Exception error) { (errors ??= new()).Add(error); }
        if (errors is { Count: 1 }) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(errors[0]).Throw();
        if (errors is { Count: > 1 }) throw new AggregateException(errors);
    }

    public void Dispose()
    {
        IReadOnlyList<IDisposable> retired;
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            var removed = values.Values.ToArray();
            values.Clear();
            retired = RetireUnowned(removed);
            owner.Dispose();
        }
        Release(retired);
    }
}
