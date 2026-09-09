using System.Net.NetworkInformation;
using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

internal sealed class WindowsNetworkCollector : ITelemetryCollector
{
    private static readonly ProviderId WindowsProviderId = new("windows");
    private readonly IReadOnlyDictionary<DeviceId, string> nativeIds;
    private readonly TimeProvider timeProvider;
    private readonly Dictionary<DeviceId, Sample> previous = [];

    public WindowsNetworkCollector(IReadOnlyDictionary<DeviceId, string> nativeIds, TimeProvider timeProvider)
    {
        this.nativeIds = nativeIds;
        this.timeProvider = timeProvider;
    }

    public CollectorId Id => new("windows.network");
    public ProviderId ProviderId => WindowsProviderId;
    public TimeSpan Cadence => TimeSpan.FromMilliseconds(500);
    public TimeSpan Timeout => TimeSpan.FromSeconds(1);

    public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var now = timeProvider.GetUtcNow();
        var interfaces = NetworkInterface.GetAllNetworkInterfaces().ToDictionary(item => item.Id, StringComparer.Ordinal);
        var observations = new List<MetricObservation>();

        foreach (var target in nativeIds)
        {
            if (!interfaces.TryGetValue(target.Value, out var networkInterface))
            {
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkReceiveRate, now));
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkTransmitRate, now));
                continue;
            }

            var statistics = networkInterface.GetIPv4Statistics();
            var current = new Sample(statistics.BytesReceived, statistics.BytesSent, now);
            if (!previous.TryGetValue(target.Key, out var prior))
            {
                previous[target.Key] = current;
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkReceiveRate, now));
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkTransmitRate, now));
                continue;
            }

            previous[target.Key] = current;
            var elapsed = (current.At - prior.At).TotalSeconds;
            if (elapsed <= 0 || current.Received < prior.Received || current.Sent < prior.Sent)
            {
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkReceiveRate, now));
                observations.Add(Unavailable(target.Key, MetricCatalog.NetworkTransmitRate, now));
                continue;
            }

            observations.Add(MetricObservation.Available(
                target.Key, MetricCatalog.NetworkReceiveRate, (current.Received - prior.Received) / elapsed,
                UnitId.BytesPerSecond, WindowsProviderId, MetricQuality.PlatformNative, now));
            observations.Add(MetricObservation.Available(
                target.Key, MetricCatalog.NetworkTransmitRate, (current.Sent - prior.Sent) / elapsed,
                UnitId.BytesPerSecond, WindowsProviderId, MetricQuality.PlatformNative, now));
        }

        return ValueTask.FromResult<IReadOnlyList<MetricObservation>>(observations);
    }

    private static MetricObservation Unavailable(DeviceId id, MetricId metricId, DateTimeOffset now) =>
        MetricObservation.Unavailable(id, metricId, UnitId.BytesPerSecond, WindowsProviderId,
            MetricQuality.PlatformNative, now, MetricAvailability.Unavailable);

    private readonly record struct Sample(long Received, long Sent, DateTimeOffset At);
}
