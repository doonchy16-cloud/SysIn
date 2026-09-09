using SysIn.Core;
using SysIn.Platform.Windows;
using SysIn.Telemetry;

namespace SysIn.Native.Tests;

public sealed class WindowsCollectorContractTests
{
    [Fact]
    public async Task Windows_provider_discovers_exactly_one_cpu_memory_and_system_device()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var provider = new WindowsProvider(TimeProvider.System);
        var devices = await provider.DiscoverAsync(CancellationToken.None);

        Assert.Single(devices.Where(device => device.Kind == DeviceKind.Cpu));
        Assert.Single(devices.Where(device => device.Kind == DeviceKind.Memory));
        Assert.Single(devices.Where(device => device.Kind == DeviceKind.System));
    }

    [Fact]
    public async Task Every_discovered_gpu_has_a_unique_opaque_id_and_no_inferred_role()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var provider = new WindowsProvider(TimeProvider.System);
        var gpus = (await provider.DiscoverAsync(CancellationToken.None))
            .Where(device => device.Kind == DeviceKind.Gpu)
            .ToArray();

        Assert.Equal(gpus.Length, gpus.Select(gpu => gpu.Id).Distinct().Count());
        Assert.All(gpus, gpu => Assert.DoesNotContain("PCI\\", gpu.Id.Value, StringComparison.OrdinalIgnoreCase));
        Assert.All(gpus, gpu => Assert.Empty(gpu.Roles));
    }

    [Fact]
    public async Task Workstream_one_does_not_advertise_unproven_gpu_utilization()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var provider = new WindowsProvider(TimeProvider.System);
        await provider.DiscoverAsync(CancellationToken.None);

        Assert.DoesNotContain(
            provider.Capabilities,
            capability => capability.DeviceKind == DeviceKind.Gpu && capability.MetricId == MetricCatalog.GpuUtilization);
    }

    [Fact]
    public async Task Non_available_windows_observations_never_use_numeric_zero_as_missing_data()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var provider = new WindowsProvider(TimeProvider.System);
        var devices = await provider.DiscoverAsync(CancellationToken.None);
        var collectors = provider.CreateCollectors(devices);

        foreach (var collector in collectors)
        {
            var observations = await collector.CollectAsync(CancellationToken.None);
            Assert.All(
                observations.Where(observation => observation.Availability != MetricAvailability.Available),
                observation => Assert.Null(observation.Value));
        }
    }
}
