using System.Runtime.InteropServices;

namespace NaviApps.DesktopApplications.Tests;

[TestClass]
public sealed class WindowsApplicationResourcesTests
{
    [TestMethod]
    [OSCondition(ConditionMode.Exclude, OperatingSystems.Windows)]
    public void WindowsResourcesAndDiscoveryRejectOtherPlatforms()
    {
        Assert.Throws<PlatformNotSupportedException>(() => new WindowsApplicationManager().GetRunningApplications());
        using var resources = new WindowsApplicationResources();
        Assert.Throws<PlatformNotSupportedException>(() => resources.GetDisplayName(@"C:\fixture.exe"));
        Assert.Throws<PlatformNotSupportedException>(() => resources.GetIcon(@"C:\fixture.exe"));
    }

    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    public void OwnedExecutableMetadataAndIconsAreAvailable()
    {
        var path = Environment.ProcessPath;
        Assert.IsNotNull(path);
        using var resources = new WindowsApplicationResources();
        Assert.IsFalse(string.IsNullOrEmpty(resources.GetDisplayName(path)));
        using var icon = resources.GetIcon(path);
        Assert.IsNotNull(icon);
    }

    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    public void IconLookupRejectsRelativePathsAndMissingExecutables()
    {
        using var resources = new WindowsApplicationResources();
        Assert.Throws<ArgumentException>(() => resources.GetIcon("relative.exe"));
        var missing = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".exe");
        Assert.IsNull(resources.GetDisplayName(missing));
        Assert.IsNull(resources.GetIcon(missing));
    }

    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    public void ReturnedIconsSurviveCacheDisposal()
    {
        var path = Environment.ProcessPath;
        Assert.IsNotNull(path);
        using var resources = new WindowsApplicationResources();
        using var first = resources.GetIcon(path);
        using var second = resources.GetIcon(path);
        Assert.IsNotNull(first);
        Assert.IsNotNull(second);
        Assert.AreNotEqual(first.DangerousGetHandle(), second.DangerousGetHandle());
        resources.Invalidate();
        resources.Dispose();
        // CopyIcon verifies that invalidation and disposal leave the caller's native resource live.
        var copy = CopyIcon(first);
        Assert.AreNotEqual(IntPtr.Zero, copy);
        DestroyIcon(copy);
    }

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern IntPtr CopyIcon(WindowsApplicationIcon icon);
    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}
