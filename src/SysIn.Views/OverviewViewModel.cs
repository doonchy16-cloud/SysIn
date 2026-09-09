using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Views;

public sealed record OverviewGpu(string Name, string Utilization);

public sealed record OverviewViewModel(
    string MachineName,
    string CpuName,
    string CpuUtilization,
    IReadOnlyList<OverviewGpu> Gpus,
    string Memory,
    string Storage,
    string Network,
    string Uptime,
    string ProviderHealth,
    string Fps,
    string FrameTime)
{
    public static OverviewViewModel FromSnapshot(SystemSnapshot snapshot, RenderStats renderStats)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(renderStats);

        var cpu = First(snapshot, DeviceKind.Cpu);
        var memory = First(snapshot, DeviceKind.Memory);
        var volume = First(snapshot, DeviceKind.Volume);
        var network = First(snapshot, DeviceKind.NetworkAdapter);
        var system = First(snapshot, DeviceKind.System);
        var gpus = snapshot.Devices.Values
            .Where(device => device.Kind == DeviceKind.Gpu)
            .OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase)
            .Select(device => new OverviewGpu(
                device.Name,
                FormatPercent(Find(snapshot, device.Id, MetricCatalog.GpuUtilization))))
            .ToArray();

        var memoryUsed = Find(snapshot, memory?.Id, MetricCatalog.MemoryUsed)?.Value;
        var memoryAvailable = Find(snapshot, memory?.Id, MetricCatalog.MemoryAvailable)?.Value;
        var memoryText = memoryUsed is { } used && memoryAvailable is { } available
            ? $"{ToGiB(used):0.0}/{ToGiB(used + available):0.0} GiB"
            : "N/A";

        var storageUsed = Find(snapshot, volume?.Id, MetricCatalog.StorageUsed)?.Value;
        var storageCapacity = Find(snapshot, volume?.Id, MetricCatalog.StorageCapacity)?.Value;
        var storageText = storageUsed is { } diskUsed && storageCapacity is { } diskCapacity
            ? $"{ToGiB(diskUsed):0}/{ToGiB(diskCapacity):0} GiB"
            : "N/A";

        var down = Find(snapshot, network?.Id, MetricCatalog.NetworkReceiveRate)?.Value;
        var up = Find(snapshot, network?.Id, MetricCatalog.NetworkTransmitRate)?.Value;
        var networkText = down is { } receive && up is { } transmit
            ? $"↓{ToMiB(receive):0.0} ↑{ToMiB(transmit):0.0} MiB/s"
            : "N/A";

        var uptimeValue = Find(snapshot, system?.Id, MetricCatalog.SystemUptime)?.Value;
        var uptime = uptimeValue is { } seconds
            ? $"{Math.Floor(seconds / 86400d):0}d"
            : "N/A";

        var healthy = snapshot.CollectorHealth.Values.Count(item => item.State == CollectorState.Healthy);
        var providerHealth = snapshot.CollectorHealth.Count == 0
            ? "N/A"
            : $"{healthy}/{snapshot.CollectorHealth.Count}";

        return new OverviewViewModel(
            system?.Name ?? "Local machine",
            cpu?.Name ?? "CPU",
            FormatPercent(Find(snapshot, cpu?.Id, MetricCatalog.CpuUtilization)),
            gpus,
            memoryText,
            storageText,
            networkText,
            uptime,
            providerHealth,
            $"{renderStats.ActualFps:0.0}/{renderStats.TargetFps:0}",
            $"{renderStats.LastFrameTime.TotalMilliseconds:0.0} ms");
    }

    private static DeviceDescriptor? First(SystemSnapshot snapshot, DeviceKind kind) =>
        snapshot.Devices.Values.FirstOrDefault(device => device.Kind == kind);

    private static MetricObservation? Find(SystemSnapshot snapshot, DeviceId? deviceId, MetricId metricId)
    {
        if (deviceId is null)
        {
            return null;
        }

        return snapshot.Metrics.TryGetValue(new MetricKey(deviceId.Value, metricId), out var observation)
            ? observation
            : null;
    }

    private static string FormatPercent(MetricObservation? observation) =>
        observation is { Availability: MetricAvailability.Available, Value: { } value }
            ? $"{value:0.#}%"
            : "N/A";

    private static double ToGiB(double bytes) => bytes / 1024d / 1024d / 1024d;
    private static double ToMiB(double bytes) => bytes / 1024d / 1024d;
}
