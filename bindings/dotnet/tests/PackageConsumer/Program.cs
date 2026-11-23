using NaviApps.DesktopApplications;

var identifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Bundle, " com.example.app ");
if (identifier.Value != "com.example.app") throw new System.Diagnostics.UnreachableException("Identifier normalization failed.");

var identity = new ApplicationProcessIdentity(40, 100);
var application = new ApplicationSnapshot(identity, identifier, "Caf\u00e9", false);
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

if (OperatingSystem.IsWindows()) new WindowsApplicationManager().GetRunningApplications();
Console.WriteLine("Clean NuGet DesktopApplications consumer passed.");
