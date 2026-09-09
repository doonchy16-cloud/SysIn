using System.Threading;
using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Native.Tests;

public sealed class CollectorSchedulerTests
{
    private sealed class CountingCollector : ITelemetryCollector
    {
        private int count;
        public CollectorId Id { get; }
        public ProviderId ProviderId => new("test");
        public TimeSpan Cadence { get; }
        public TimeSpan Timeout => TimeSpan.FromSeconds(1);
        public int Count => Volatile.Read(ref count);

        public CountingCollector(string id, TimeSpan cadence)
        {
            Id = new CollectorId(id);
            Cadence = cadence;
        }

        public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref count);
            return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([]);
        }
    }

    private sealed class RealDelay : ICollectorDelay
    {
        public async ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken) =>
            await Task.Delay(delay, cancellationToken);
    }

    [Fact]
    public async Task Collectors_run_independently_at_their_own_cadence_and_pause_stops_collection()
    {
        var fast = new CountingCollector("fast", TimeSpan.FromMilliseconds(10));
        var slow = new CountingCollector("slow", TimeSpan.FromMilliseconds(60));
        var store = new TelemetryStore(new FreshnessPolicy());
        var supervisor = new CollectorSupervisor(TimeProvider.System);

        await using var scheduler = new CollectorScheduler(
            [fast, slow], supervisor, store, new RealDelay(), CancellationToken.None);

        scheduler.Start();
        await Task.Delay(180);

        Assert.True(fast.Count > slow.Count, $"fast={fast.Count}, slow={slow.Count}");
        Assert.True(slow.Count >= 1);

        scheduler.SetPaused(true);
        await Task.Delay(80);
        var fastPaused = fast.Count;
        var slowPaused = slow.Count;
        await Task.Delay(80);

        Assert.Equal(fastPaused, fast.Count);
        Assert.Equal(slowPaused, slow.Count);
        Assert.True(scheduler.IsPaused);
    }
}
