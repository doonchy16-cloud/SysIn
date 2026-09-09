using SysIn.Core;

namespace SysIn.Providers;

public enum ProviderTrust
{
    DirectVendor = 0,
    PlatformNative = 1,
    AuditedFallback = 2,
    Experimental = 3
}

public sealed record ProviderDescriptor(
    ProviderId Id,
    string Name,
    ProviderTrust Trust);

public sealed record TelemetryCapability(
    DeviceKind DeviceKind,
    MetricId MetricId);

public interface ITelemetryProvider
{
    ProviderDescriptor Descriptor { get; }
    IReadOnlySet<TelemetryCapability> Capabilities { get; }
    ValueTask<IReadOnlyList<DeviceDescriptor>> DiscoverAsync(CancellationToken cancellationToken);
    IReadOnlyList<ITelemetryCollector> CreateCollectors(IReadOnlyList<DeviceDescriptor> devices);
}

public interface ITelemetryCollector
{
    CollectorId Id { get; }
    ProviderId ProviderId { get; }
    TimeSpan Cadence { get; }
    TimeSpan Timeout { get; }
    ValueTask<IReadOnlyList<MetricObservation>> CollectAsync(CancellationToken cancellationToken);
}
