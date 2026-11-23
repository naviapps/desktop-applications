using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using NaviApps.DesktopApplications;

internal static class WindowsAcceptance
{
    private sealed class Observation : IAsyncDisposable
    {
        private readonly CancellationTokenSource cancellation = new(TimeSpan.FromSeconds(30));
        private readonly IAsyncEnumerator<ApplicationEvent> stream;
        private Task<bool>? next;
        internal Observation(WindowsApplicationManager manager)
        {
            stream = manager.ObserveAsync(
                [ApplicationLifecycle.Launched, ApplicationLifecycle.Terminated],
                TimeSpan.FromMilliseconds(50), cancellation.Token).GetAsyncEnumerator();
            next = stream.MoveNextAsync().AsTask();
        }
        internal async Task Expect(ApplicationLifecycle lifecycle, uint processId)
        {
            while (next is not null && await next)
            {
                var current = stream.Current;
                next = stream.MoveNextAsync().AsTask();
                if (current.Lifecycle == lifecycle && current.Application.Identity.ProcessId == processId) return;
            }
            throw new System.Diagnostics.UnreachableException("Application observation ended before the owned event.");
        }
        public async ValueTask DisposeAsync()
        {
            cancellation.Cancel();
            try { if (next is not null) await next; }
            catch (OperationCanceledException) { }
            await stream.DisposeAsync();
            cancellation.Dispose();
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new System.Diagnostics.UnreachableException(message); }
    private static string ReceiptText(string path)
    {
        // Polling must not deny the owned UI thread access while it records readiness or close acknowledgements.
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
    private static async Task Wait(Func<bool> predicate)
    {
        var until = Stopwatch.StartNew();
        while (!predicate())
        {
            if (until.Elapsed > TimeSpan.FromSeconds(15)) throw new TimeoutException("Owned application did not reach its expected state.");
            await Task.Delay(50);
        }
    }
    private static async Task Main(string[] args)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        if (args.Length != 1) throw new ArgumentException("Select one owned Windows test executable.");
        Require(RuntimeInformation.ProcessArchitecture == Architecture.X64, "Owned Windows acceptance requires an x64 .NET process.");
        var target = Path.GetFullPath(args[0]);
        var manager = new WindowsApplicationManager();
        var work = Path.Combine(Path.GetTempPath(), "desktop-applications-" + Guid.NewGuid());
        Directory.CreateDirectory(work);
        try
        {
            foreach (string mode in new[] { "accept", "refuse" })
            {
                string receipt = Path.Combine(work, mode + ".json");
                await using var observation = new Observation(manager);
                uint pid = manager.LaunchApplication(target, new[] { receipt, mode });
                using var owned = Process.GetProcessById(checked((int)pid));
                using var terminationCancellation = new CancellationTokenSource();
                ApplicationSnapshot? captured = null;
                try
                {
                    await Wait(() =>
                    {
                        try
                        {
                            using var doc = JsonDocument.Parse(ReceiptText(receipt));
                            return doc.RootElement.TryGetProperty("ready", out var ready) && ready.GetBoolean()
                                && doc.RootElement.GetProperty("processId").GetUInt32() == pid
                                && manager.GetRunningApplications().Any(a => a.Identity.ProcessId == pid);
                        }
                        catch (IOException) { return false; }
                        catch (JsonException) { return false; }
                    });
                    Console.WriteLine("Owned target ready: " + ReceiptText(receipt));
                    captured = manager.GetApplication(pid);
                    await observation.Expect(ApplicationLifecycle.Launched, pid);
                    Require(captured.Identity.StartTime != 0 && captured.Identifier?.Kind == ApplicationIdentifierKind.Executable, "Native identity missing.");
                    var stale = captured with { Identity = captured.Identity with { StartTime = captured.Identity.StartTime + 1 } };
                    try { manager.TerminateApplication(stale); throw new System.Diagnostics.UnreachableException("Stale native target accepted."); }
                    catch (ApplicationOperationException e) { Require(e.Code == ApplicationOperationErrorCode.TargetChanged, "Wrong stale identity failure."); }
                    Require(!owned.HasExited, "Stale operation affected the owned process.");
                    try { manager.ActivateApplication(captured); }
                    catch (ApplicationOperationException e) when (e.Code == ApplicationOperationErrorCode.RequestRejected)
                    { Console.WriteLine("Windows foreground policy rejected activation; rejection was preserved."); }
                    var termination = manager.WaitForApplicationTerminationAsync(
                        captured.Identifier!, TimeSpan.FromMilliseconds(50), TimeSpan.FromSeconds(30),
                        terminationCancellation.Token);
                    manager.TerminateApplication(captured);
                    if (mode == "accept")
                    {
                        await Wait(() => owned.HasExited);
                    }
                    else
                    {
                        await Wait(() =>
                        {
                            try { using var doc = JsonDocument.Parse(ReceiptText(receipt)); return doc.RootElement.GetProperty("closeRequests").GetInt32() >= 2; }
                            catch (IOException) { return false; }
                            catch (JsonException) { return false; }
                        });
                        Require(!owned.HasExited, "Graceful close bypassed the application's refusal.");
                        manager.TerminateApplication(captured, force: true);
                        await Wait(() => owned.HasExited);
                    }
                    await observation.Expect(ApplicationLifecycle.Terminated, pid);
                    var ended = await termination;
                    Require(ended?.Identity == captured.Identity && ended.Terminated,
                        "Identifier-filtered wait did not return the owned termination.");
                }
                catch
                {
                    owned.Refresh();
                    Console.WriteLine("Owned target diagnostics: " + JsonSerializer.Serialize(new
                    {
                        pid,
                        mode,
                        exited = owned.HasExited,
                        title = owned.HasExited ? null : owned.MainWindowTitle,
                        receipt = File.Exists(receipt) ? ReceiptText(receipt) : null,
                        dotnetRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT")
                    }));
                    try { Console.WriteLine("Owned native snapshot: " + JsonSerializer.Serialize(manager.GetApplication(pid))); }
                    catch (Exception error) { Console.WriteLine("Owned query failure: " + error); }
                    throw;
                }
                finally
                {
                    terminationCancellation.Cancel();
                    // Cleanup is bounded to the process created by this fixture.
                    if (!owned.HasExited)
                    {
                        owned.Kill();
                        await owned.WaitForExitAsync();
                    }
                }
            }
            Console.WriteLine("Owned separate-process launch, enumeration, stale identity, multi-window graceful refusal and force acceptance passed.");
        }
        finally { Directory.Delete(work, true); }
    }
}
