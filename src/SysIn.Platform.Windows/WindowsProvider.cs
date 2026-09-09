using System.Net.NetworkInformation;
using SysIn.Core;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.Platform.Windows;

public sealed class WindowsProvider : ITelemetryProvider
{
    private readonly TimeProvider timeProvider;
    private Dictionary<DeviceId, string> networkNativeIds = [];
    private Dictionary<DeviceId, string> volumeRoots = [];

    public WindowsProvider(TimeProvider timeProvider)
    {
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public ProviderDescriptor Descriptor { get; } = new(
        new ProviderId("windows"),
        "Windows Native",
        ProviderTrust.PlatformNative);

    public IReadOnlySet<TelemetryCapability> Capabilities { get; } = new HashSet<TelemetryCapability>
    {
        new(DeviceKind.Cpu, MetricCatalog.CpuUtilization),
        new(DeviceKind.Memory, MetricCatalog.MemoryUsed),
        new(DeviceKind.Memory, MetricCatalog.MemoryAvailable),
        new(DeviceKind.Memory, MetricCatalog.MemoryUtilization),
        new(DeviceKind.Volume, MetricCatalog.StorageUsed),
        new(DeviceKind.Volume, MetricCatalog.StorageCapacity),
        new(DeviceKind.NetworkAdapter, MetricCatalog.NetworkReceiveRate),
        new(DeviceKind.NetworkAdapter, MetricCatalog.NetworkTransmitRate),
        new(DeviceKind.System, MetricCatalog.SystemUptime)
    };

    public ValueTask<IReadOnlyList<DeviceDescriptor>> DiscoverAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var devices = new List<DeviceDescriptor>();

        var processorIdentity = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "Windows CPU";
        var cpu = new DeviceDescriptor(
            DeviceIdFactory.Create(DeviceKind.Cpu, processorIdentity, Environment.ProcessorCount.ToString()),
            DeviceKind.Cpu,
            processorIdentity,
            null,
            null,
            new HashSet<DeviceRole>());
        devices.Add(cpu);

        devices.Add(new DeviceDescriptor(
            DeviceIdFactory.Create(DeviceKind.Memory, "physical-memory"),
            DeviceKind.Memory,
            "Physical Memory",
            null,
            null,
            new HashSet<DeviceRole>()));

        devices.Add(new DeviceDescriptor(
            DeviceIdFactory.Create(DeviceKind.System, Environment.MachineName),
            DeviceKind.System,
            Environment.MachineName,
            "Microsoft Windows",
            Environment.OSVersion.VersionString,
            new HashSet<DeviceRole>()));

        devices.AddRange(WindowsGpuDiscovery.Discover());

        var networkMap = new Dictionary<DeviceId, string>();
        foreach (var networkInterface in NetworkInterface.GetAllNetworkInterfaces()
                     .Where(item => item.OperationalStatus == OperationalStatus.Up && item.NetworkInterfaceType != NetworkInterfaceType.Loopback))
        {
            var id = DeviceIdFactory.Create(DeviceKind.NetworkAdapter, networkInterface.Id);
            networkMap[id] = networkInterface.Id;
            devices.Add(new DeviceDescriptor(
                id,
                DeviceKind.NetworkAdapter,
                networkInterface.Name,
                null,
                networkInterface.Description,
                new HashSet<DeviceRole>()));
        }

        var rootMap = new Dictionary<DeviceId, string>();
        foreach (var drive in DriveInfo.GetDrives().Where(drive => drive.DriveType == DriveType.Fixed && drive.IsReady))
        {
            var id = DeviceIdFactory.Create(DeviceKind.Volume, drive.Name);
            rootMap[id] = drive.Name;
            devices.Add(new DeviceDescriptor(
                id,
                DeviceKind.Volume,
                drive.Name,
                null,
                drive.DriveFormat,
                new HashSet<DeviceRole>()));
        }

        networkNativeIds = networkMap;
        volumeRoots = rootMap;
        return ValueTask.FromResult<IReadOnlyList<DeviceDescriptor>>(devices);
    }

    public IReadOnlyList<ITelemetryCollector> CreateCollectors(IReadOnlyList<DeviceDescriptor> devices)
    {
        ArgumentNullException.ThrowIfNull(devices);
        var collectors = new List<ITelemetryCollector>();

        var cpu = devices.SingleOrDefault(device => device.Kind == DeviceKind.Cpu);
        if (cpu is not null)
        {
            collectors.Add(new WindowsCpuCollector(cpu.Id));
        }

        var memory = devices.SingleOrDefault(device => device.Kind == DeviceKind.Memory);
        if (memory is not null)
        {
            collectors.Add(new WindowsMemoryCollector(memory.Id));
        }

        var system = devices.SingleOrDefault(device => device.Kind == DeviceKind.System);
        if (system is not null)
        {
            collectors.Add(new WindowsSystemCollector(system.Id));
        }

        if (networkNativeIds.Count > 0)
        {
            collectors.Add(new WindowsNetworkCollector(networkNativeIds, timeProvider));
        }

        if (volumeRoots.Count > 0)
        {
            collectors.Add(new WindowsVolumeCollector(volumeRoots));
        }

        return collectors;
    }
}
