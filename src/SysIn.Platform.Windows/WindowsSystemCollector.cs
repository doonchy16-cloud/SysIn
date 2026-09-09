using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

internal sealed class WindowsSystemCollector : ITelemetryCollector
{
    private static readonly ProviderId WindowsProviderId = new("windows");
    private readonly DeviceId deviceId;

    public WindowsSystemCollector(DeviceId deviceId)
    {
        this.deviceId = deviceId;
    }

    public CollectorId Id => new("windows.system");
    public ProviderId ProviderId => WindowsProviderId;
    public TimeSpan Cadence => TimeSpan.FromSeconds(1);
    public TimeSpan Timeout => TimeSpan.FromSeconds(1);

    public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var uptimeSeconds = Math.Max(0d, Environment.TickCount64 / 1000d);
        return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
            MetricObservation.Available(deviceId, MetricCatalog.SystemUptime, uptimeSeconds, UnitId.Seconds,
                WindowsProviderId, MetricQuality.PlatformNative, DateTimeOffset.UtcNow)]);
    }
}
