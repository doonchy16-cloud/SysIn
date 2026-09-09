using System.Runtime.InteropServices;
using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

internal sealed partial class WindowsMemoryCollector : ITelemetryCollector
{
    private static readonly ProviderId WindowsProviderId = new("windows");
    private readonly DeviceId deviceId;

    public WindowsMemoryCollector(DeviceId deviceId)
    {
        this.deviceId = deviceId;
    }

    public CollectorId Id => new("windows.memory");
    public ProviderId ProviderId => WindowsProviderId;
    public TimeSpan Cadence => TimeSpan.FromMilliseconds(500);
    public TimeSpan Timeout => TimeSpan.FromSeconds(1);

    public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var now = DateTimeOffset.UtcNow;
        var status = new MemoryStatusEx { Length = (uint)Marshal.SizeOf<MemoryStatusEx>() };

        if (GlobalMemoryStatusEx(ref status) == 0 || status.TotalPhysical == 0)
        {
            return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
                Unavailable(MetricCatalog.MemoryUsed, UnitId.Bytes, now),
                Unavailable(MetricCatalog.MemoryAvailable, UnitId.Bytes, now),
                Unavailable(MetricCatalog.MemoryUtilization, UnitId.Percent, now)]);
        }

        var used = status.TotalPhysical - status.AvailablePhysical;
        var utilization = Math.Clamp(100d * used / status.TotalPhysical, 0d, 100d);

        return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
            MetricObservation.Available(deviceId, MetricCatalog.MemoryUsed, used, UnitId.Bytes,
                WindowsProviderId, MetricQuality.PlatformNative, now),
            MetricObservation.Available(deviceId, MetricCatalog.MemoryAvailable, status.AvailablePhysical, UnitId.Bytes,
                WindowsProviderId, MetricQuality.PlatformNative, now),
            MetricObservation.Available(deviceId, MetricCatalog.MemoryUtilization, utilization, UnitId.Percent,
                WindowsProviderId, MetricQuality.PlatformNative, now)]);
    }

    private MetricObservation Unavailable(MetricId metricId, UnitId unit, DateTimeOffset now) =>
        MetricObservation.Unavailable(deviceId, metricId, unit, WindowsProviderId,
            MetricQuality.PlatformNative, now, MetricAvailability.ProviderError);

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial int GlobalMemoryStatusEx(ref MemoryStatusEx buffer);
}
