using System.Collections.Concurrent;
using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Providers;

public sealed record CollectorRunResult(
    bool Succeeded,
    bool Skipped,
    int ObservationCount,
    string? ErrorClass);

public sealed class CollectorSupervisor
{
    private readonly TimeProvider timeProvider;
    private readonly int failureThreshold;
    private readonly TimeSpan circuitDuration;
    private readonly ConcurrentDictionary<CollectorId, CollectorHealth> health = new();

    public CollectorSupervisor(
        TimeProvider timeProvider,
        int failureThreshold = 3,
        TimeSpan? circuitDuration = null)
    {
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        if (failureThreshold < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(failureThreshold));
        }

        this.failureThreshold = failureThreshold;
        this.circuitDuration = circuitDuration ?? TimeSpan.FromSeconds(5);
        if (this.circuitDuration < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(circuitDuration));
        }
    }

    public CollectorHealth GetHealth(CollectorId id) =>
        health.TryGetValue(id, out var current)
            ? current
            : new CollectorHealth(id, CollectorState.Healthy, 0, null, null, null, null, null);

    public async ValueTask<CollectorRunResult> RunOnceAsync(
        ITelemetryCollector collector,
        TelemetryStore store,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(collector);
        ArgumentNullException.ThrowIfNull(store);

        var now = timeProvider.GetUtcNow();
        var previous = GetHealth(collector.Id);
        if (previous.State == CollectorState.CircuitOpen && previous.CircuitOpenUntil is { } until && now < until)
        {
            return new CollectorRunResult(false, true, 0, previous.LastErrorClass);
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(collector.Timeout);
        var started = timeProvider.GetTimestamp();

        try
        {
            var observations = await collector.CollectAsync(timeout.Token).ConfigureAwait(false);
            store.PublishRange(observations);

            var completedAt = timeProvider.GetUtcNow();
            var completed = new CollectorHealth(
                collector.Id,
                CollectorState.Healthy,
                0,
                completedAt,
                completedAt,
                timeProvider.GetElapsedTime(started),
                null,
                null);
            health[collector.Id] = completed;
            store.SetCollectorHealth(completed);

            return new CollectorRunResult(true, false, observations.Count, null);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return RecordFailure(collector, store, previous, "Timeout", started);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return RecordFailure(collector, store, previous, exception.GetType().Name, started);
        }
    }

    private CollectorRunResult RecordFailure(
        ITelemetryCollector collector,
        TelemetryStore store,
        CollectorHealth previous,
        string errorClass,
        long started)
    {
        var failedAt = timeProvider.GetUtcNow();
        var failures = previous.ConsecutiveFailures + 1;
        var circuitOpen = failures >= failureThreshold;
        var current = new CollectorHealth(
            collector.Id,
            circuitOpen ? CollectorState.CircuitOpen : CollectorState.Degraded,
            failures,
            failedAt,
            previous.LastSuccess,
            timeProvider.GetElapsedTime(started),
            errorClass,
            circuitOpen ? failedAt + circuitDuration : null);

        health[collector.Id] = current;
        store.SetCollectorHealth(current);
        return new CollectorRunResult(false, false, 0, errorClass);
    }
}
