using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace NaviApps.DesktopApplications;

internal sealed record TargetRequest(ApplicationSnapshot Expected, ApplicationSnapshot Actual);
internal sealed record ReconcileRequest(ApplicationState Previous, ApplicationState Current);
internal sealed record EventIdentity(ApplicationLifecycle Lifecycle, ApplicationIdentifier? Identifier);
internal sealed record EventSelection(ApplicationLifecycle[] Lifecycles, ApplicationIdentifier? Identifier, IEnumerable<EventIdentity> Candidates);
internal sealed record EmptyRequest;
internal sealed record ProcessRequest(uint ProcessId);
internal sealed record LaunchRequest(string Executable, IReadOnlyList<string> Arguments);
internal sealed record ControlRequest(ApplicationSnapshot Target, bool Force);
internal sealed record ResolveResource(string Action, ApplicationResourceIdentity Resource);
internal sealed record InvalidateResources(string Action, ApplicationIdentifier? Identifier);
internal sealed record ResourceGeneration(string Action, ulong Generation);
internal sealed record ResourceTransition(ulong? Generation, IReadOnlyList<ulong> EvictedGenerations, bool LoadIsCurrent);

[JsonSourceGenerationOptions(GenerationMode = JsonSourceGenerationMode.Metadata)]
[JsonSerializable(typeof(ApplicationIdentifier))]
[JsonSerializable(typeof(ApplicationTargetValidationError))]
[JsonSerializable(typeof(ApplicationReconciliation))]
[JsonSerializable(typeof(ApplicationSnapshot[]))]
[JsonSerializable(typeof(TargetRequest))]
[JsonSerializable(typeof(ReconcileRequest))]
[JsonSerializable(typeof(EventSelection))]
[JsonSerializable(typeof(EmptyRequest))]
[JsonSerializable(typeof(ProcessRequest))]
[JsonSerializable(typeof(LaunchRequest))]
[JsonSerializable(typeof(ControlRequest))]
[JsonSerializable(typeof(ResolveResource))]
[JsonSerializable(typeof(InvalidateResources))]
[JsonSerializable(typeof(ResourceGeneration))]
[JsonSerializable(typeof(ResourceTransition))]
[JsonSerializable(typeof(int[]))]
internal sealed partial class ApplicationJson : JsonSerializerContext
{
    private static readonly ApplicationJson Wire = new(new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters =
        {
            new JsonStringEnumConverter<ApplicationIdentifierKind>(JsonNamingPolicy.CamelCase),
            new JsonStringEnumConverter<ApplicationLifecycle>(JsonNamingPolicy.CamelCase),
            new JsonStringEnumConverter<ApplicationTargetValidationError>(JsonNamingPolicy.CamelCase),
            new ExactStringConverter(),
        }
    });

    internal static JsonTypeInfo<T> Type<T>() => (JsonTypeInfo<T>)Wire.GetTypeInfo(typeof(T))!;

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
