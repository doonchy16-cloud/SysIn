namespace SysIn.Core;

public enum CollectorState
{
    Healthy,
    Degraded,
    Retrying,
    CircuitOpen
}

public sealed record CollectorHealth(
    CollectorId Id,
    CollectorState State,
    int ConsecutiveFailures,
    DateTimeOffset? LastAttempt,
    DateTimeOffset? LastSuccess,
    TimeSpan? LastDuration,
    string? LastErrorClass,
    DateTimeOffset? CircuitOpenUntil);
