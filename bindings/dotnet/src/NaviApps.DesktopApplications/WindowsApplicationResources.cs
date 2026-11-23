using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace NaviApps.DesktopApplications;

/// <summary>An owned Windows HICON. Dispose after use. This is not an encoded or portable image.</summary>
public sealed class WindowsApplicationIcon : SafeHandleZeroOrMinusOneIsInvalid
{
    internal WindowsApplicationIcon(IntPtr handle) : base(true) => SetHandle(handle);
    protected override bool ReleaseHandle() => DestroyIcon(handle);
    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}

/// <summary>Metadata and Shell icons for explicit absolute .exe paths, matching the Windows backend's
/// executable identity. No package/AUMID discovery, product symbols or process selection is implied.
/// Shell lookup is synchronous; the host chooses its scheduling. Dispose to release cached HICONs.</summary>
public sealed class WindowsApplicationResources : IDisposable
{
    private readonly object gate = new();
    private readonly ApplicationResourceCache<string> names = new();
    private readonly ApplicationResourceCache<WindowsApplicationIcon> icons = new();
    private bool disposed;

    public string? GetDisplayName(string executable)
    {
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var identity = Identity(executable, "displayName");
            if (identity is null) return null;
            return names.Get(identity, () =>
            {
                var description = FileVersionInfo.GetVersionInfo(executable).FileDescription;
                return string.IsNullOrEmpty(description) ? Path.GetFileNameWithoutExtension(executable) : description;
            });
        }
    }

    /// <summary>Returns an independently owned HICON, or null if unavailable. The caller disposes it;
    /// subsequent SDK invalidation/disposal cannot destroy the returned copy.</summary>
    public WindowsApplicationIcon? GetIcon(string executable, bool small = false)
    {
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var identity = Identity(executable, small ? "icon:small" : "icon:large");
            if (identity is null) return null;
            var cached = icons.Get(identity, () => LoadIcon(executable, small));
            if (cached is null) return null;
            var copy = CopyIcon(cached);
            return copy == IntPtr.Zero ? null : new WindowsApplicationIcon(copy);
        }
    }

    /// <summary>Call after native resource/theme changes not reflected in file metadata.</summary>
    public void Invalidate(ApplicationIdentifier? identifier = null)
    {
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            names.Invalidate(identifier);
            icons.Invalidate(identifier);
        }
    }

    private ApplicationResourceIdentity? Identity(string executable, string variant)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows application resources require Windows.");
        if (!Path.IsPathFullyQualified(executable) || !Path.GetExtension(executable).Equals(".exe", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("An explicit absolute .exe path is required.", nameof(executable));
        var identifier = ApplicationIdentifier.Create(ApplicationIdentifierKind.Executable, executable);
        var info = new FileInfo(executable);
        if (!info.Exists)
        {
            names.Invalidate(identifier);
            icons.Invalidate(identifier);
            return null;
        }
        var revision = FormattableString.Invariant($"{info.Length}:{info.LastWriteTimeUtc.Ticks}:{info.CreationTimeUtc.Ticks}");
        return new(identifier, info.FullName, revision, variant + ":" + CultureInfo.CurrentUICulture.Name);
    }

    private static WindowsApplicationIcon? LoadIcon(string executable, bool small)
    {
        // SHGetFileInfo requires COM on the calling thread. Balance only our successful initialization.
        int initialized = CoInitializeEx(IntPtr.Zero, 2);
        const int changedMode = unchecked((int)0x80010106);
        if (initialized < 0 && initialized != changedMode) Marshal.ThrowExceptionForHR(initialized);
        try
        {
            nuint result = SHGetFileInfoW(executable, 0, out var info, (uint)Marshal.SizeOf<ShellFileInfo>(), 0x100u | (small ? 1u : 0u));
            if (info.Icon == IntPtr.Zero) return null;
            var icon = new WindowsApplicationIcon(info.Icon);
            if (result != 0) return icon;
            icon.Dispose();
            return null;
        }
        finally { if (initialized >= 0) CoUninitialize(); }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            names.Dispose();
            icons.Dispose();
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShellFileInfo
    {
        public IntPtr Icon;
        public int IconIndex;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName;
    }
    [DllImport("shell32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern nuint SHGetFileInfoW(string path, uint attributes, out ShellFileInfo info, uint size, uint flags);
    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern IntPtr CopyIcon(WindowsApplicationIcon icon);
    [DllImport("ole32.dll", ExactSpelling = true)]
    private static extern int CoInitializeEx(IntPtr reserved, uint flags);
    [DllImport("ole32.dll", ExactSpelling = true)]
    private static extern void CoUninitialize();
}
