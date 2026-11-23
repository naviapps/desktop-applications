using System.Runtime.InteropServices;
using NaviApps.DesktopApplications;

internal static class WindowsApplicationResourcesTests
{
    internal static void Run()
    {
        var path = Environment.ProcessPath ?? throw new System.Diagnostics.UnreachableException("Missing owned test executable.");
        using var resources = new WindowsApplicationResources();
        if (string.IsNullOrEmpty(resources.GetDisplayName(path))) throw new System.Diagnostics.UnreachableException("Owned executable metadata unavailable.");
        try { resources.GetIcon("relative.exe"); throw new System.Diagnostics.UnreachableException("Relative icon path accepted."); }
        catch (ArgumentException) { }
        var missing = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".exe");
        if (resources.GetDisplayName(missing) is not null || resources.GetIcon(missing) is not null)
            throw new System.Diagnostics.UnreachableException("Missing executable produced fallback resources.");
        using var first = resources.GetIcon(path) ?? throw new System.Diagnostics.UnreachableException("Owned executable icon unavailable.");
        using var second = resources.GetIcon(path) ?? throw new System.Diagnostics.UnreachableException("Cached native icon unavailable.");
        if (first.DangerousGetHandle() == second.DangerousGetHandle()) throw new System.Diagnostics.UnreachableException("Caller received a borrowed cached HICON.");
        resources.Invalidate();
        resources.Dispose();
        // CopyIcon verifies that invalidation/disposal did not destroy the caller's native resource.
        var copy = CopyIcon(first);
        if (copy == IntPtr.Zero) throw new System.Diagnostics.UnreachableException("SDK disposal destroyed the caller's HICON.");
        DestroyIcon(copy);
        Console.WriteLine("Owned Windows executable metadata and independent HICON lifetime passed.");
    }

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern IntPtr CopyIcon(WindowsApplicationIcon icon);
    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}
