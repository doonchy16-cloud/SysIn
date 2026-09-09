using SysIn.Core;

namespace SysIn.Providers;

public sealed class ProviderRegistry
{
    private readonly IReadOnlyList<ITelemetryProvider> providers;

    public ProviderRegistry(IEnumerable<ITelemetryProvider> providers)
    {
        ArgumentNullException.ThrowIfNull(providers);
        this.providers = providers.ToArray();
    }

    public ITelemetryProvider? Resolve(TelemetryCapability capability) =>
        providers
            .Where(provider => provider.Capabilities.Contains(capability))
            .OrderBy(provider => provider.Descriptor.Trust)
            .ThenBy(provider => provider.Descriptor.Id.Value, StringComparer.Ordinal)
            .FirstOrDefault();
}
