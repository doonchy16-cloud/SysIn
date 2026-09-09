using SysIn.Core;

namespace SysIn.Telemetry;

public readonly record struct MetricKey(DeviceId DeviceId, MetricId MetricId);

public sealed record SystemSnapshot(
    IReadOnlyDictionary<DeviceId, DeviceDescriptor> Devices,
    IReadOnlyDictionary<MetricKey, MetricObservation> Metrics,
    IReadOnlyDictionary<CollectorId, CollectorHealth> CollectorHealth,
    DateTimeOffset CapturedAt);
