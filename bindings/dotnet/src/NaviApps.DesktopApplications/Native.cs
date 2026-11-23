using System.Runtime.InteropServices;
using System.Text.Json;

namespace NaviApps.DesktopApplications;

internal static partial class Native
{
    private const string Library = "desktop_applications";
    [DllImport(Library, EntryPoint = "desktop_applications_abi_version", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint AbiVersion();
    [DllImport(Library, EntryPoint = "desktop_applications_query", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr Query(uint operation, byte[] data, nuint size);
    [DllImport(Library, EntryPoint = "desktop_applications_buffer_data", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr Data(IntPtr owner, out nuint size);
    [DllImport(Library, EntryPoint = "desktop_applications_buffer_free", CallingConvention = CallingConvention.Cdecl)]
    private static extern void Free(IntPtr owner);

    internal static JsonElement Call<T>(uint operation, T input)
    {
        EnsureAbi();
        var data = JsonSerializer.SerializeToUtf8Bytes(input, ApplicationJson.Type<T>());
        IntPtr owner = Query(operation, data, (nuint)data.Length);
        return Consume(owner);
    }
    private static void EnsureAbi()
    {
        if (AbiVersion() != 2) throw new InvalidOperationException("Native ABI mismatch.");
    }
    private static JsonElement Consume(IntPtr owner)
    {
        if (owner == IntPtr.Zero) throw new InvalidOperationException("Native application query failed.");
        try
        {
            IntPtr pointer = Data(owner, out nuint length);
            if (pointer == IntPtr.Zero || length > 64 * 1024 * 1024) throw new InvalidOperationException("Invalid native response.");
            var bytes = new byte[checked((int)length)];
            Marshal.Copy(pointer, bytes, 0, bytes.Length);
            using var document = JsonDocument.Parse(bytes);
            if (document.RootElement.TryGetProperty("error", out var error)) throw new ArgumentException(error.GetString());
            return document.RootElement.GetProperty("value").Clone();
        }
        finally { Free(owner); }
    }
    internal static T Decode<T>(JsonElement element) =>
        element.Deserialize(ApplicationJson.Type<T>()) ?? throw new InvalidOperationException("Missing native value.");
}
