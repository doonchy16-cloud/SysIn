using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Native.Tests;

public sealed class CollectorSupervisorTests
{
    private sealed class ThrowingCollector : ITelemetryCollector
    {
        public CollectorId Id => new("throwing");
        public ProviderId ProviderId => new("test");
        public TimeSpan Cadence => TimeSpan.FromMilliseconds(20);
        public TimeSpan Timeout => TimeSpan.FromMilliseconds(100);

        public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken) =>
            ValueTask.FromException<IReadOnlyList<MetricObservation>>(new InvalidOperationException("test"));
    }

    [Fact]
    public async Task Exception_is_contained_and_health_becomes_degraded()
    {
        var store = new TelemetryStore(new FreshnessPolicy());
        var supervisor = new CollectorSupervisor(TimeProvider.System);
        var collector = new ThrowingCollector();

        var result = await supervisor.RunOnceAsync(collector, store, CancellationToken.None);

        Assert.False(result.Succeeded);
        Assert.False(result.Skipped);
        Assert.Equal("InvalidOperationException", result.ErrorClass);
        Assert.Equal(CollectorState.Degraded, supervisor.GetHealth(collector.Id).State);
        Assert.Equal(CollectorState.Degraded, store.BuildSnapshot(DateTimeOffset.UtcNow).CollectorHealth[collector.Id].State);
    }

    [Fact]
    public async Task Third_consecutive_failure_opens_circuit_and_next_call_is_skipped()
    {
        var store = new TelemetryStore(new FreshnessPolicy());
        var supervisor = new CollectorSupervisor(TimeProvider.System, 3, TimeSpan.FromSeconds(5));
        var collector = new ThrowingCollector();

        await supervisor.RunOnceAsync(collector, store, CancellationToken.None);
        await supervisor.RunOnceAsync(collector, store, CancellationToken.None);
        await supervisor.RunOnceAsync(collector, store, CancellationToken.None);

        Assert.Equal(CollectorState.CircuitOpen, supervisor.GetHealth(collector.Id).State);

        var skipped = await supervisor.RunOnceAsync(collector, store, CancellationToken.None);
        Assert.True(skipped.Skipped);
        Assert.False(skipped.Succeeded);
    }
}
