using System.Collections.Frozen;
using SysIn.Core;

namespace SysIn.Telemetry;

public sealed class TelemetryStore
{
    private readonly object gate = new();
    private readonly FreshnessPolicy freshnessPolicy;
    private readonly Dictionary<DeviceId, DeviceDescriptor> devices = [];
    private readonly Dictionary<MetricKey, MetricObservation> metrics = [];
    private readonly Dictionary<CollectorId, CollectorHealth> collectorHealth = [];

    public TelemetryStore(FreshnessPolicy freshnessPolicy)
    {
        this.freshnessPolicy = freshnessPolicy ?? throw new ArgumentNullException(nameof(freshnessPolicy));
    }

    public void RegisterDevices(IEnumerable<DeviceDescriptor> devicesToRegister)
    {
        ArgumentNullException.ThrowIfNull(devicesToRegister);

        lock (gate)
        {
            foreach (var device in devicesToRegister)
            {
                var frozenRoles = device.Roles.ToFrozenSet();
                devices[device.Id] = device with { Roles = frozenRoles };
            }
        }
    }

    public void Publish(MetricObservation observation)
    {
        lock (gate)
        {
            metrics[new MetricKey(observation.DeviceId, observation.MetricId)] = observation;
        }
    }

    public void PublishRange(IEnumerable<MetricObservation> observations)
    {
        ArgumentNullException.ThrowIfNull(observations);

        lock (gate)
        {
            foreach (var observation in observations)
            {
                metrics[new MetricKey(observation.DeviceId, observation.MetricId)] = observation;
            }
        }
    }

    public void SetCollectorHealth(CollectorHealth health)
    {
        ArgumentNullException.ThrowIfNull(health);

        lock (gate)
        {
            collectorHealth[health.Id] = health;
        }
    }

    public SystemSnapshot BuildSnapshot(DateTimeOffset now)
    {
        lock (gate)
        {
            var snapshotDevices = devices.ToFrozenDictionary();
            var snapshotMetrics = metrics.ToFrozenDictionary(
                pair => pair.Key,
                pair => pair.Value with
                {
                    Freshness = freshnessPolicy.Evaluate(pair.Value, now)
                });
            var snapshotHealth = collectorHealth.ToFrozenDictionary();

            return new SystemSnapshot(snapshotDevices, snapshotMetrics, snapshotHealth, now);
        }
    }
}
