using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Native.Tests;

internal static class TestFixtures
{
    private static readonly DateTimeOffset Now = new(2026, 9, 9, 4, 0, 0, TimeSpan.Zero);

    public static SystemSnapshot DualGpuSnapshot()
    {
        var cpu = Device("cpu:fixture", DeviceKind.Cpu, "Intel Core Test CPU");
        var intel = Device("gpu:intel", DeviceKind.Gpu, "Intel Iris Xe");
        var nvidia = Device("gpu:nvidia", DeviceKind.Gpu, "NVIDIA GeForce RTX Test");
        var memory = Device("memory:fixture", DeviceKind.Memory, "Physical Memory");
        var volume = Device("volume:c", DeviceKind.Volume, "C:\\");
        var network = Device("network:wifi", DeviceKind.NetworkAdapter, "Wi-Fi");
        var system = Device("system:fixture", DeviceKind.System, "Test-PC");

        var devices = new[] { cpu, intel, nvidia, memory, volume, network, system }
            .ToDictionary(device => device.Id);
        var metrics = new Dictionary<MetricKey, MetricObservation>();

        Add(metrics, cpu.Id, MetricCatalog.CpuUtilization, 37, UnitId.Percent);
        Add(metrics, memory.Id, MetricCatalog.MemoryUsed, 21.4 * 1024 * 1024 * 1024, UnitId.Bytes);
        Add(metrics, memory.Id, MetricCatalog.MemoryAvailable, 10.0 * 1024 * 1024 * 1024, UnitId.Bytes);
        Add(metrics, memory.Id, MetricCatalog.MemoryUtilization, 68, UnitId.Percent);
        Add(metrics, volume.Id, MetricCatalog.StorageUsed, 700d * 1024 * 1024 * 1024, UnitId.Bytes);
        Add(metrics, volume.Id, MetricCatalog.StorageCapacity, 1024d * 1024 * 1024 * 1024, UnitId.Bytes);
        Add(metrics, network.Id, MetricCatalog.NetworkReceiveRate, 24d * 1024 * 1024, UnitId.BytesPerSecond);
        Add(metrics, network.Id, MetricCatalog.NetworkTransmitRate, 3d * 1024 * 1024, UnitId.BytesPerSecond);
        Add(metrics, system.Id, MetricCatalog.SystemUptime, 27d * 24 * 60 * 60, UnitId.Seconds);

        var health = new Dictionary<CollectorId, CollectorHealth>
        {
            [new CollectorId("cpu")] = Healthy("cpu"),
            [new CollectorId("memory")] = Healthy("memory"),
            [new CollectorId("network")] = Healthy("network"),
            [new CollectorId("storage")] = Healthy("storage")
        };

        return new SystemSnapshot(devices, metrics, health, Now);
    }

    public static string RepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "SysIn.sln")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate repository root containing SysIn.sln.");
    }

    private static DeviceDescriptor Device(string id, DeviceKind kind, string name) =>
        new(new DeviceId(id), kind, name, null, null, new HashSet<DeviceRole>());

    private static void Add(
        IDictionary<MetricKey, MetricObservation> metrics,
        DeviceId deviceId,
        MetricId metricId,
        double value,
        UnitId unit)
    {
        metrics[new MetricKey(deviceId, metricId)] = MetricObservation.Available(
            deviceId, metricId, value, unit, new ProviderId("fixture"), MetricQuality.Direct, Now);
    }

    private static CollectorHealth Healthy(string id) =>
        new(new CollectorId(id), CollectorState.Healthy, 0, Now, Now, TimeSpan.FromMilliseconds(2), null, null);
}
