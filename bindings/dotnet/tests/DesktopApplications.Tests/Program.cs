using NaviApps.DesktopApplications;

static void Require(bool condition, string message)
{
    if (!condition) throw new System.Diagnostics.UnreachableException(message);
}

static void RequireArgumentRejection(Action operation, string message)
{
    try { operation(); }
    catch (ArgumentException) { return; }
    throw new System.Diagnostics.UnreachableException(message);
}

var identifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, " com.Example.App\n");
Require(identifier.Value == "com.Example.App", "Bundle normalization changed identity.");
const string malformedExecutable = "C:\\Apps\\\uD800.exe";
const string validExecutable = "C:\\Apps\\\U0001F680.exe";
RequireArgumentRejection(
    () => ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, malformedExecutable),
    "Malformed UTF-16 reached Rust as a different executable identifier.");
Require(ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, validExecutable).Value == validExecutable, "Paired UTF-16 did not round-trip.");
const string composed = "caf\u00e9.app";
const string decomposed = "cafe\u0301.app";
var composedIdentifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, composed);
var decomposedIdentifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, decomposed);
Require(composedIdentifier.Value == composed && decomposedIdentifier.Value == decomposed, "Executable spelling changed.");
Require(new[] { composedIdentifier, decomposedIdentifier }.Distinct().Count() == 2, "Distinct executable spellings aliased.");
var composedResource = new ApplicationResourceIdentity(composedIdentifier, composed, composed, composed);
var resourcesBySpelling = new[]
{
    composedResource,
    composedResource with { Location = decomposed },
    composedResource with { Revision = decomposed },
    composedResource with { Variant = decomposed },
};
Require(resourcesBySpelling.Distinct().Count() == resourcesBySpelling.Length, "Distinct resource spellings aliased.");
var identity = new ApplicationProcessIdentity(40, 100);
var snapshot = new ApplicationSnapshot(identity, identifier, "Caf\u00e9", false);
Require(snapshot.ValidateAgainst(snapshot) is null, "Live identity rejected.");
var decomposedName = snapshot with { DisplayName = "Cafe\u0301" };
Require(new[] { snapshot, decomposedName }.Distinct().Count() == 2, "Distinct display name spellings aliased.");
Require(new ApplicationEvent(ApplicationLifecycle.Activated, snapshot) != new ApplicationEvent(ApplicationLifecycle.Activated, decomposedName),
    "Event equality ignored display name spelling.");
var literalReplacement = snapshot with { Identifier = new(ApplicationIdentifierKind.Executable, "C:\\Apps\\\uFFFD.exe") };
var malformed = snapshot with { Identifier = new(ApplicationIdentifierKind.Executable, malformedExecutable) };
Require(literalReplacement.ValidateAgainst(literalReplacement) is null, "A literal replacement character did not round-trip.");
RequireArgumentRejection(
    () => malformed.ValidateAgainst(literalReplacement),
    "Malformed and replacement executable identifiers aliased before Rust validation.");
var reused = decomposedName with { Identity = identity with { StartTime = 101 } };
Require(snapshot.ValidateAgainst(reused) == ApplicationTargetValidationError.TargetChanged, "Reused PID accepted.");
var previousApplications = new List<ApplicationSnapshot> { snapshot };
var previous = new ApplicationState(previousApplications, identity);
var nextApplications = new[] { reused };
var next = new ApplicationState(nextApplications, reused.Identity);
previousApplications[0] = reused;
nextApplications[0] = snapshot;
Require(previous.Applications[0] == snapshot && next.Applications[0] == reused,
    "Caller edits changed a captured lifecycle sample.");
var delta = previous.Reconcile(next);
Require(delta.State == next && delta.State.GetHashCode() == next.GetHashCode(),
    "Reconciliation did not preserve structural sample equality.");
Require(delta.Events.Single(e => e.Lifecycle == ApplicationLifecycle.Terminated).Application == snapshot with { Terminated = true },
    "Termination did not decode the original snapshot.");
var copiedEvents = delta.Events.ToList();
var copiedDelta = delta with { Events = copiedEvents };
var copyOfNext = next with { Applications = new List<ApplicationSnapshot> { reused } };
Require(copyOfNext == next && copyOfNext.GetHashCode() == next.GetHashCode(),
    "Sample equality must ignore the collection instance.");
copiedEvents.Reverse();
Require(copiedDelta == delta && copiedDelta.GetHashCode() == delta.GetHashCode(),
    "Editing the source collection changed captured reconciliation events.");
Require(delta with { Events = copiedEvents } != delta, "Event equality ignored ordering.");
Require(next with { Frontmost = null } != next, "State equality ignored foreground identity.");
if (delta.State.Applications is IList<ApplicationSnapshot> applications)
{
    try { applications[0] = snapshot; throw new System.Diagnostics.UnreachableException("Decoded state permits mutation."); }
    catch (NotSupportedException) { }
}
if (delta.Events is IList<ApplicationEvent> events)
{
    try { events.Clear(); throw new System.Diagnostics.UnreachableException("Decoded events permit mutation."); }
    catch (NotSupportedException) { }
}
try
{
    var sample = new ApplicationState(new[] { snapshot with { Identity = identity with { StartTime = 0 } } }, null);
    ApplicationState.Empty.Reconcile(sample);
    throw new System.Diagnostics.UnreachableException("Native rejection did not reach the managed caller.");
}
catch (ArgumentException exception) when (exception.Message == "IdentityUnavailable") { }
if (!OperatingSystem.IsWindows())
{
    try { new WindowsApplicationManager().GetRunningApplications(); throw new System.Diagnostics.UnreachableException("Windows API accepted on another platform."); }
    catch (PlatformNotSupportedException) { }
}
using (var cache = new ApplicationResourceCache<string>())
{
    var resource = new ApplicationResourceIdentity(identifier, "/selected.app", "1", "name:en");
    RequireArgumentRejection(
        () => cache.Get(resource with { Location = malformedExecutable }, () => throw new System.Diagnostics.UnreachableException("Malformed cache key reached the loader.")),
        "Malformed cache key was accepted.");
    Require(cache.Get(resource, () => null) is null, "Missing metadata cached a value.");
    Require(cache.Get(resource, () => "Selected") == "Selected", "Missing metadata was not retried.");
    Require(cache.Get(resource, () => throw new System.Diagnostics.UnreachableException("A retained hit called the loader.")) == "Selected",
        "Cache did not return its retained value.");
    cache.Invalidate(identifier);
    Require(cache.Get(resource, () => "Reloaded") == "Reloaded", "Identifier invalidation failed.");
}
var released = new OwnedResource();
using (var cache = new ApplicationResourceCache<OwnedResource>())
{
    var resource = new ApplicationResourceIdentity(identifier, "/0.app", "1", "icon");
    cache.Get(resource, () => released);
    for (int index = 1; index <= 128; index++) cache.Get(resource with { Location = $"/{index}.app" }, () => new OwnedResource());
    Require(released.Disposed, "Evicted native resource was not released.");
    var invalidated = new OwnedResource();
    cache.Get(resource, () => invalidated);
    cache.Invalidate(identifier);
    Require(invalidated.Disposed, "Invalidated native resource was not released.");
    cache.Get(resource, () => released = new OwnedResource());
}
Require(released.Disposed, "Cache disposal retained native resources.");
ResourceCacheReentrancyTests.Run(identifier);
await ApplicationEventTests.Run();
if (!OperatingSystem.IsWindows())
{
    using var resources = new WindowsApplicationResources();
    try { resources.GetDisplayName("C:\\fixture.exe"); throw new System.Diagnostics.UnreachableException("Windows metadata accepted on another platform."); }
    catch (PlatformNotSupportedException) { }
    try { resources.GetIcon("C:\\fixture.exe"); throw new System.Diagnostics.UnreachableException("Windows icon accepted on another platform."); }
    catch (PlatformNotSupportedException) { }
}
if (OperatingSystem.IsWindows()) WindowsApplicationResourcesTests.Run();
Console.WriteLine("Managed identity, lifecycle, resource cache and platform-boundary acceptance passed.");
if (args.Length == 1)
{
    if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
    await WindowsAcceptance.Run(args[0]);
}

sealed class OwnedResource : IDisposable
{
    public bool Disposed { get; private set; }
    public void Dispose() => Disposed = true;
}
