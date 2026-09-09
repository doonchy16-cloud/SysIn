using SysIn.Core;

namespace SysIn.Native.Tests;

public sealed class CoreModelTests
{
    [Fact]
    public void Unsupported_is_null_and_not_fresh()
    {
        var metric = MetricObservation.Unavailable(
            new DeviceId("gpu:test"),
            new MetricId("gpu.temperature"),
            UnitId.Celsius,
            new ProviderId("windows"),
            MetricQuality.PlatformNative,
            DateTimeOffset.UnixEpoch,
            MetricAvailability.Unsupported);

        Assert.Null(metric.Value);
        Assert.Equal(MetricFreshness.NotApplicable, metric.Freshness);
    }

    [Fact]
    public void Zero_is_valid_available_data()
    {
        var metric = MetricObservation.Available(
            new DeviceId("gpu:test"),
            new MetricId("gpu.utilization"),
            0d,
            UnitId.Percent,
            new ProviderId("test"),
            MetricQuality.Direct,
            DateTimeOffset.UnixEpoch);

        Assert.Equal(0d, metric.Value);
        Assert.Equal(MetricAvailability.Available, metric.Availability);
    }

    [Fact]
    public void Device_id_is_stable_and_opaque()
    {
        var first = DeviceIdFactory.Create(DeviceKind.Gpu, "PCI\\VEN_10DE&DEV_TEST", "RTX TEST");
        var second = DeviceIdFactory.Create(DeviceKind.Gpu, "PCI\\VEN_10DE&DEV_TEST", "RTX TEST");

        Assert.Equal(first, second);
        Assert.DoesNotContain("VEN_10DE", first.Value, StringComparison.OrdinalIgnoreCase);
    }
}
