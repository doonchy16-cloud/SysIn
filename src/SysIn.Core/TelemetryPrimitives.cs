namespace SysIn.Core;

public enum UnitId
{
    None,
    Percent,
    Bytes,
    BytesPerSecond,
    Celsius,
    Hertz,
    Watts,
    Rpm,
    Seconds
}

public enum MetricAvailability
{
    Available,
    Unsupported,
    Unavailable,
    PermissionRequired,
    ProviderError
}

public enum MetricFreshness
{
    Fresh,
    Aging,
    Stale,
    NotApplicable
}

public enum MetricQuality
{
    Direct,
    PlatformNative,
    GenericFallback
}

public sealed record MetricObservation(
    DeviceId DeviceId,
    MetricId MetricId,
    double? Value,
    UnitId Unit,
    DateTimeOffset ObservedAt,
    ProviderId ProviderId,
    MetricQuality Quality,
    MetricAvailability Availability,
    MetricFreshness Freshness)
{
    public static MetricObservation Available(
        DeviceId deviceId,
        MetricId metricId,
        double value,
        UnitId unit,
        ProviderId providerId,
        MetricQuality quality,
        DateTimeOffset observedAt) =>
        new(
            deviceId,
            metricId,
            value,
            unit,
            observedAt,
            providerId,
            quality,
            MetricAvailability.Available,
            MetricFreshness.Fresh);

    public static MetricObservation Unavailable(
        DeviceId deviceId,
        MetricId metricId,
        UnitId unit,
        ProviderId providerId,
        MetricQuality quality,
        DateTimeOffset observedAt,
        MetricAvailability availability)
    {
        if (availability == MetricAvailability.Available)
        {
            throw new ArgumentOutOfRangeException(nameof(availability), availability, "Unavailable metrics cannot use the Available state.");
        }

        return new(
            deviceId,
            metricId,
            null,
            unit,
            observedAt,
            providerId,
            quality,
            availability,
            MetricFreshness.NotApplicable);
    }
}
