using System.Runtime.InteropServices;
using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

internal sealed partial class WindowsCpuCollector : ITelemetryCollector
{
    private static readonly ProviderId WindowsProviderId = new("windows");
    private readonly DeviceId deviceId;
    private ulong? previousIdle;
    private ulong? previousKernel;
    private ulong? previousUser;

    public WindowsCpuCollector(DeviceId deviceId)
    {
        this.deviceId = deviceId;
    }

    public CollectorId Id => new("windows.cpu");
    public ProviderId ProviderId => WindowsProviderId;
    public TimeSpan Cadence => TimeSpan.FromMilliseconds(250);
    public TimeSpan Timeout => TimeSpan.FromSeconds(1);

    public ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var now = DateTimeOffset.UtcNow;

        if (GetSystemTimes(out var idle, out var kernel, out var user) == 0)
        {
            return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
                MetricObservation.Unavailable(deviceId, MetricCatalog.CpuUtilization, UnitId.Percent,
                    WindowsProviderId, MetricQuality.PlatformNative, now, MetricAvailability.ProviderError)]);
        }

        var currentIdle = idle.ToUInt64();
        var currentKernel = kernel.ToUInt64();
        var currentUser = user.ToUInt64();

        if (previousIdle is null || previousKernel is null || previousUser is null)
        {
            previousIdle = currentIdle;
            previousKernel = currentKernel;
            previousUser = currentUser;
            return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
                MetricObservation.Unavailable(deviceId, MetricCatalog.CpuUtilization, UnitId.Percent,
                    WindowsProviderId, MetricQuality.PlatformNative, now, MetricAvailability.Unavailable)]);
        }

        var idleDelta = currentIdle - previousIdle.Value;
        var kernelDelta = currentKernel - previousKernel.Value;
        var userDelta = currentUser - previousUser.Value;
        previousIdle = currentIdle;
        previousKernel = currentKernel;
        previousUser = currentUser;

        var total = kernelDelta + userDelta;
        if (total == 0)
        {
            return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
                MetricObservation.Unavailable(deviceId, MetricCatalog.CpuUtilization, UnitId.Percent,
                    WindowsProviderId, MetricQuality.PlatformNative, now, MetricAvailability.Unavailable)]);
        }

        var busy = total >= idleDelta ? total - idleDelta : 0UL;
        var utilization = Math.Clamp(100d * busy / total, 0d, 100d);

        return ValueTask.FromResult<IReadOnlyList<MetricObservation>>([
            MetricObservation.Available(deviceId, MetricCatalog.CpuUtilization, utilization, UnitId.Percent,
                WindowsProviderId, MetricQuality.PlatformNative, now)]);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeFileTime
    {
        public uint Low;
        public uint High;
        public readonly ulong ToUInt64() => ((ulong)High << 32) | Low;
    }

    [LibraryImport("kernel32.dll")]
    private static partial int GetSystemTimes(
        out NativeFileTime idleTime,
        out NativeFileTime kernelTime,
        out NativeFileTime userTime);
}
