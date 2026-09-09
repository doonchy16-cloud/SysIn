using SysIn.Core;
using SysIn.Providers;

namespace SysIn.Native.Tests;

public sealed class ProviderRegistryTests
{
    private sealed class FakeProvider : ITelemetryProvider
    {
        public ProviderDescriptor Descriptor { get; }
        public IReadOnlySet<TelemetryCapability> Capabilities { get; }

        public FakeProvider(string id, ProviderTrust trust, TelemetryCapability capability)
        {
            Descriptor = new ProviderDescriptor(new ProviderId(id), id, trust);
            Capabilities = new HashSet<TelemetryCapability> { capability };
        }

        public ValueTask<IReadOnlyList<DeviceDescriptor>> DiscoverAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult<IReadOnlyList<DeviceDescriptor>>([]);

        public IReadOnlyList<ITelemetryCollector> CreateCollectors(IReadOnlyList<DeviceDescriptor> devices) => [];
    }

    [Fact]
    public void Vendor_outranks_platform()
    {
        var capability = new TelemetryCapability(DeviceKind.Gpu, new MetricId("gpu.utilization"));
        var registry = new ProviderRegistry([
            new FakeProvider("windows", ProviderTrust.PlatformNative, capability),
            new FakeProvider("nvidia", ProviderTrust.DirectVendor, capability)]);

        Assert.Equal(new ProviderId("nvidia"), registry.Resolve(capability)!.Descriptor.Id);
    }

    [Fact]
    public void Provider_id_breaks_equal_trust_ties_ordinally()
    {
        var capability = new TelemetryCapability(DeviceKind.Gpu, new MetricId("gpu.utilization"));
        var registry = new ProviderRegistry([
            new FakeProvider("vendor-z", ProviderTrust.DirectVendor, capability),
            new FakeProvider("vendor-a", ProviderTrust.DirectVendor, capability)]);

        Assert.Equal(new ProviderId("vendor-a"), registry.Resolve(capability)!.Descriptor.Id);
    }

    [Fact]
    public void Missing_capability_resolves_to_null()
    {
        var offered = new TelemetryCapability(DeviceKind.Cpu, new MetricId("cpu.utilization"));
        var requested = new TelemetryCapability(DeviceKind.Gpu, new MetricId("gpu.temperature"));
        var registry = new ProviderRegistry([new FakeProvider("windows", ProviderTrust.PlatformNative, offered)]);

        Assert.Null(registry.Resolve(requested));
    }
}
