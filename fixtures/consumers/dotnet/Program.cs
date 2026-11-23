using NaviApps.DesktopApplications;

#if NATIVE_AOT_FIXTURE
if (System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported)
    throw new System.Diagnostics.UnreachableException("The fixture requires Native AOT execution.");
#endif
AppContext.SetSwitch("System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault", false);
if (System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault)
    throw new System.Diagnostics.UnreachableException("The fixture requires JSON reflection to be disabled.");

var identifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, " com.example.app ");
if (identifier.Value != "com.example.app") throw new System.Diagnostics.UnreachableException("Identifier normalization failed.");

var identity = new ApplicationProcessIdentity(40, 100);
var application = new ApplicationSnapshot(identity, identifier, "Caf\u00e9", false);
var reusedIdentity = application with { Identity = identity with { StartTime = 101 } };
if (application.ValidateAgainst(application) is not null || application.ValidateAgainst(reusedIdentity) != ApplicationTargetValidationError.TargetChanged)
    throw new System.Diagnostics.UnreachableException("Packaged process validation accepted a reused identity.");
var applications = new[] { application };
var current = new ApplicationState(applications, identity);
applications[0] = application with { Terminated = true };
var change = ApplicationState.Empty.Reconcile(current);
if (change.State != current || !change.Events.Select(e => e.Lifecycle).SequenceEqual(new[] { ApplicationLifecycle.Launched, ApplicationLifecycle.Activated }))
    throw new System.Diagnostics.UnreachableException("Packaged lifecycle reconciliation failed.");

var next = new ApplicationState(new[] { application with { DisplayName = "Cafe\u0301" } }, identity);
var metadataChange = current.Reconcile(next);
if (metadataChange.State != next || metadataChange.State == current || metadataChange.Events.Count != 0)
    throw new System.Diagnostics.UnreachableException("Packaged snapshot equality ignored display name spelling.");

using var cache = new ApplicationResourceCache<string>();
var resource = new ApplicationResourceIdentity(identifier, "Synthetic", "1", "name");
if (cache.Get(resource, () => "Fixture") != "Fixture")
    throw new System.Diagnostics.UnreachableException("Packaged resource load failed.");
try
{
    cache.Invalidate(new ApplicationIdentifier(ApplicationIdentifierKind.Bundle, " \t"));
    throw new System.Diagnostics.UnreachableException("Packaged cache accepted an invalid identifier.");
}
catch (ArgumentException error) when (error.Message == "InvalidIdentifier") { }
if (cache.Get(resource, () => "Unexpected reload") != "Fixture")
    throw new System.Diagnostics.UnreachableException("Invalid input cleared a packaged resource.");
cache.Invalidate(identifier);
if (cache.Get(resource, () => "Reloaded") != "Reloaded")
    throw new System.Diagnostics.UnreachableException("Packaged cache did not reload after invalidation.");

if (OperatingSystem.IsWindows())
{
    new WindowsApplicationManager().GetRunningApplications();
#if NATIVE_AOT_FIXTURE
    var executable = Environment.ProcessPath ?? throw new System.Diagnostics.UnreachableException("Missing process path.");
    using var resources = new WindowsApplicationResources();
    using var icon = resources.GetIcon(executable);
    if (resources.GetDisplayName(executable) is null || icon is null || icon.IsInvalid)
        throw new System.Diagnostics.UnreachableException("The published executable's name or Shell icon was unavailable.");
#endif
}
Console.WriteLine("Clean NuGet DesktopApplications consumer passed.");
