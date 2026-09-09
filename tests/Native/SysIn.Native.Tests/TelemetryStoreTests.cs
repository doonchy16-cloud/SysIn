using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Native.Tests;

public sealed class TelemetryStoreTests
{
    private static readonly DeviceDescriptor Cpu = new(
        new DeviceId("cpu:test"),
        DeviceKind.Cpu,
        "Test CPU",
        null,
        null,
        new HashSet<DeviceRole>());

    [Fact]
    public void Earlier_snapshot_is_not_mutated_by_later_publications()
    {
        var store = new TelemetryStore(new FreshnessPolicy());
        store.RegisterDevices([Cpu]);
        store.Publish(MetricObservation.Available(
            Cpu.Id,
            MetricCatalog.CpuUtilization,
            10d,
            UnitId.Percent,
            new ProviderId("test"),
            MetricQuality.Direct,
            DateTimeOffset.UnixEpoch));

        var first = store.BuildSnapshot(DateTimeOffset.UnixEpoch);

        store.Publish(MetricObservation.Available(
            Cpu.Id,
            MetricCatalog.CpuUtilization,
            90d,
            UnitId.Percent,
            new ProviderId("test"),
            MetricQuality.Direct,
            DateTimeOffset.UnixEpoch.AddSeconds(1)));

        Assert.Equal(10d, first.Metrics[new MetricKey(Cpu.Id, MetricCatalog.CpuUtilization)].Value);
    }

    [Fact]
    public void Available_value_becomes_stale_without_becoming_zero()
    {
        var store = new TelemetryStore(new FreshnessPolicy());
        store.RegisterDevices([Cpu]);
        store.Publish(MetricObservation.Available(
            Cpu.Id,
            MetricCatalog.CpuUtilization,
            42d,
            UnitId.Percent,
            new ProviderId("test"),
            MetricQuality.Direct,
            DateTimeOffset.UnixEpoch));

        var snapshot = store.BuildSnapshot(DateTimeOffset.UnixEpoch.AddSeconds(6));
        var metric = snapshot.Metrics[new MetricKey(Cpu.Id, MetricCatalog.CpuUtilization)];

        Assert.Equal(42d, metric.Value);
        Assert.Equal(MetricFreshness.Stale, metric.Freshness);
    }

    [Fact]
    public void Collector_health_is_part_of_snapshot()
    {
        var store = new TelemetryStore(new FreshnessPolicy());
        var health = new CollectorHealth(
            new CollectorId("cpu"),
            CollectorState.Healthy,
            0,
            DateTimeOffset.UnixEpoch,
            DateTimeOffset.UnixEpoch,
            TimeSpan.FromMilliseconds(2),
            null,
            null);

        store.SetCollectorHealth(health);
        var snapshot = store.BuildSnapshot(DateTimeOffset.UnixEpoch);

        Assert.Equal(CollectorState.Healthy, snapshot.CollectorHealth[new CollectorId("cpu")].State);
    }
}
