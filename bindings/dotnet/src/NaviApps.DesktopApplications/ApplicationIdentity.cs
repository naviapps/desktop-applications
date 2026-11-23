namespace NaviApps.DesktopApplications;

public enum ApplicationIdentifierKind { Bundle, Executable, AppUserModel }
public sealed record ApplicationIdentifier(ApplicationIdentifierKind Kind, string Value)
{
    public static ApplicationIdentifier Create(ApplicationIdentifierKind kind, string value) =>
        Native.Decode<ApplicationIdentifier>(Native.Call(1, new ApplicationIdentifier(kind, value)));
}
/// <summary>Creation time is an opaque OS-native token, never a cross-platform timestamp.</summary>
public sealed record ApplicationProcessIdentity(uint ProcessId, ulong StartTime);
public sealed record ApplicationSnapshot(ApplicationProcessIdentity Identity, ApplicationIdentifier? Identifier, string? DisplayName, bool Terminated)
{
    public ApplicationTargetValidationError? ValidateAgainst(ApplicationSnapshot actual)
    {
        var value = Native.Call(2, new TargetRequest(this, actual));
        return value.ValueKind == System.Text.Json.JsonValueKind.Null ? null : Native.Decode<ApplicationTargetValidationError>(value);
    }
}
public enum ApplicationTargetValidationError
{
    InvalidIdentifier, InvalidProcessId, IdentityUnavailable, TargetChanged,
    IdentifierUnavailable, IdentifierMismatch, Terminated, DuplicateProcess
}
public enum ApplicationLifecycle { Launched, Terminated, Activated, Deactivated }
public sealed record ApplicationEvent(ApplicationLifecycle Lifecycle, ApplicationSnapshot Application);
/// <summary>An immutable sample of applications in their recorded order.</summary>
public sealed record ApplicationState(IReadOnlyList<ApplicationSnapshot> Applications, ApplicationProcessIdentity? Frontmost)
{
    private IReadOnlyList<ApplicationSnapshot> applications = Array.AsReadOnly(Applications.ToArray());

    public IReadOnlyList<ApplicationSnapshot> Applications
    {
        get => applications;
        init => applications = Array.AsReadOnly(value.ToArray());
    }

    public static ApplicationState Empty { get; } = new(Array.Empty<ApplicationSnapshot>(), null);
    public ApplicationReconciliation Reconcile(ApplicationState current) =>
        Native.Decode<ApplicationReconciliation>(Native.Call(3, new ReconcileRequest(this, current)));

    public bool Equals(ApplicationState? other) =>
        ReferenceEquals(this, other) ||
        other is not null && Frontmost == other.Frontmost && Applications.SequenceEqual(other.Applications);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Frontmost);
        foreach (var application in Applications) hash.Add(application);
        return hash.ToHashCode();
    }
}

/// <summary>The normalized sample and ordered lifecycle transitions returned by reconciliation.</summary>
public sealed record ApplicationReconciliation(ApplicationState State, IReadOnlyList<ApplicationEvent> Events)
{
    private IReadOnlyList<ApplicationEvent> events = Array.AsReadOnly(Events.ToArray());

    public IReadOnlyList<ApplicationEvent> Events
    {
        get => events;
        init => events = Array.AsReadOnly(value.ToArray());
    }

    public bool Equals(ApplicationReconciliation? other) =>
        ReferenceEquals(this, other) ||
        other is not null && State == other.State && Events.SequenceEqual(other.Events);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(State);
        foreach (var item in Events) hash.Add(item);
        return hash.ToHashCode();
    }
}
