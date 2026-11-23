using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NaviApps.DesktopApplications;

internal static partial class Native
{
    private const string Library = "desktop_applications";
    internal static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase), new ExactStringConverter() }
    };
    static Native() => NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, Resolve);
    private static IntPtr Resolve(string name, Assembly assembly, DllImportSearchPath? search)
    {
        if (name != Library) return IntPtr.Zero;
        var explicitPath = Environment.GetEnvironmentVariable("DESKTOP_APPLICATIONS_NATIVE_LIBRARY");
        if (explicitPath is not null) return NativeLibrary.Load(explicitPath);
        string file = OperatingSystem.IsWindows() ? Library + ".dll" : "lib" + Library + ".dylib";
        string packaged = Path.Combine(AppContext.BaseDirectory, "runtimes", RuntimeInformation.RuntimeIdentifier, "native", file);
        return File.Exists(packaged) ? NativeLibrary.Load(packaged) : NativeLibrary.Load(file, assembly, search);
    }
    [DllImport(Library, EntryPoint = "desktop_applications_abi_version", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint AbiVersion();
    [DllImport(Library, EntryPoint = "desktop_applications_query", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr Query(uint operation, byte[] data, nuint size);
    [DllImport(Library, EntryPoint = "desktop_applications_buffer_data", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr Data(IntPtr owner, out nuint size);
    [DllImport(Library, EntryPoint = "desktop_applications_buffer_free", CallingConvention = CallingConvention.Cdecl)]
    private static extern void Free(IntPtr owner);

    internal static JsonElement Call(uint operation, object input)
    {
        EnsureAbi();
        var data = JsonSerializer.SerializeToUtf8Bytes(input, Json);
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
    internal static T Decode<T>(JsonElement element) => element.Deserialize<T>(Json) ?? throw new InvalidOperationException("Missing native value.");

    private sealed class ExactStringConverter : JsonConverter<string>
    {
        private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

        public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            reader.GetString();

        public override void Write(Utf8JsonWriter writer, string value, JsonSerializerOptions options)
        {
            // The JSON writer would replace an unpaired surrogate before Rust could reject it.
            _ = StrictUtf8.GetByteCount(value);
            writer.WriteStringValue(value);
        }
    }
}
