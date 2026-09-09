using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

internal sealed class WindowsVolumeCollector : ITelemetryCollector
{
    private static readonly ProviderId WindowsProviderId = new("windows");
    private readonly IReadOnlyDictionary<DeviceId, string> roots;

    public WindowsVolumeCollector(IReadOnlyDictionary<DeviceId, string> roots)
    {
        this.roots = roots;
    }

    public CollectorId Id => new("windows.volumes");
    public ProviderId ProviderId => WindowsProviderId;
    public TimeSpan Cadence => TimeSpan.FromSeconds(2);
    public TimeSpan Timeout => TimeSpan.FromSeconds(1);

    public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var now = DateTimeOffset.UtcNow;
        var observations = new List<MetricObservation>();

        foreach (var target in roots)
        {
            try
            {
                var drive = new DriveInfo(target.Value);
                if (!drive.IsReady || drive.DriveType != DriveType.Fixed)
                {
                    AddUnavailable(observations, target.Key, now);
                    continue;
                }

                var capacity = (double)drive.TotalSize;
                var used = (double)(drive.TotalSize - drive.AvailableFreeSpace);
                observations.Add(MetricObservation.Available(target.Key, MetricCatalog.StorageCapacity, capacity,
                    UnitId.Bytes, WindowsProviderId, MetricQuality.PlatformNative, now));
                observations.Add(MetricObservation.Available(target.Key, MetricCatalog.StorageUsed, used,
                    UnitId.Bytes, WindowsProviderId, MetricQuality.PlatformNative, now));
            }
            catch (IOException)
            {
                AddUnavailable(observations, target.Key, now);
            }
            catch (UnauthorizedAccessException)
            {
                AddUnavailable(observations, target.Key, now);
            }
        }

        return ValueTask.FromResult<IReadOnlyList<MetricObservation>>(observations);
    }

    private static void AddUnavailable(List<MetricObservation> observations, DeviceId id, DateTimeOffset now)
    {
        observations.Add(MetricObservation.Unavailable(id, MetricCatalog.StorageCapacity, UnitId.Bytes,
            WindowsProviderId, MetricQuality.PlatformNative, now, MetricAvailability.Unavailable));
        observations.Add(MetricObservation.Unavailable(id, MetricCatalog.StorageUsed, UnitId.Bytes,
            WindowsProviderId, MetricQuality.PlatformNative, now, MetricAvailability.Unavailable));
    }
}
