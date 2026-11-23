using System.Runtime.InteropServices;
using System.Text.Json;

namespace NaviApps.DesktopApplications;

internal sealed class ResourceCacheHandle : SafeHandle
{
    internal ResourceCacheHandle(IntPtr value) : base(IntPtr.Zero, true) => SetHandle(value);
    public override bool IsInvalid => handle == IntPtr.Zero;
    protected override bool ReleaseHandle() { Native.DestroyResourceCache(handle); return true; }
}

internal static partial class Native
{
    [DllImport(Library, EntryPoint = "desktop_applications_resource_cache_create", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr CreateResourceCacheNative();
    [DllImport(Library, EntryPoint = "desktop_applications_resource_cache_query", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr QueryResourceCacheNative(ResourceCacheHandle owner, byte[] input, nuint length);
    [DllImport(Library, EntryPoint = "desktop_applications_resource_cache_destroy", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void DestroyResourceCache(IntPtr owner);

    internal static ResourceCacheHandle CreateResourceCache()
    {
        EnsureAbi();
        var owner = new ResourceCacheHandle(CreateResourceCacheNative());
        if (owner.IsInvalid) { owner.Dispose(); throw new InvalidOperationException("Native cache owner unavailable."); }
        return owner;
    }
    internal static JsonElement QueryResourceCache(ResourceCacheHandle owner, object action)
    {
        var input = JsonSerializer.SerializeToUtf8Bytes(action, Json);
        return Consume(QueryResourceCacheNative(owner, input, (nuint)input.Length));
    }
}
