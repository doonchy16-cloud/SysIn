using System.Text.Json;
using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Cli;

public static class SnapshotJsonFormatter
{
    private sealed record JsonMetricRow(
        string deviceId,
        string metricId,
        double? value,
        string unit,
        DateTimeOffset observedAt,
        string providerId,
        string quality,
        string status,
        string freshness);

    public static string Format(SystemSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        var devices = snapshot.Devices.Values
            .OrderBy(device => device.Kind)
            .ThenBy(device => device.Name, StringComparer.Ordinal)
            .Select(device => new
            {
                id = device.Id.Value,
                kind = Camel(device.Kind.ToString()),
                name = device.Name,
                vendor = device.Vendor,
                model = device.Model,
                roles = device.Roles.Select(role => Camel(role.ToString())).OrderBy(role => role, StringComparer.Ordinal).ToArray()
            })
            .ToArray();

        var metrics = snapshot.Metrics.Values
            .Select(ToMetricRow)
            .Concat(MaterializeRequiredOverviewMetrics(snapshot))
            .OrderBy(metric => metric.deviceId, StringComparer.Ordinal)
            .ThenBy(metric => metric.metricId, StringComparer.Ordinal)
            .ToArray();

        var collectorHealth = snapshot.CollectorHealth.Values
            .OrderBy(health => health.Id.Value, StringComparer.Ordinal)
            .Select(health => new
            {
                id = health.Id.Value,
                state = Camel(health.State.ToString()),
                consecutiveFailures = health.ConsecutiveFailures,
                lastAttempt = health.LastAttempt,
                lastSuccess = health.LastSuccess,
                lastDurationMs = health.LastDuration?.TotalMilliseconds,
                lastErrorClass = health.LastErrorClass,
                circuitOpenUntil = health.CircuitOpenUntil
            })
            .ToArray();

        var payload = new
        {
            schemaVersion = "1.0-preview",
            capturedAt = snapshot.CapturedAt,
            devices,
            metrics,
            collectorHealth
        };

        return JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
    }

    private static IEnumerable<JsonMetricRow> MaterializeRequiredOverviewMetrics(SystemSnapshot snapshot)
    {
        foreach (var gpu in snapshot.Devices.Values.Where(device => device.Kind == DeviceKind.Gpu))
        {
            var key = new MetricKey(gpu.Id, MetricCatalog.GpuUtilization);
            if (snapshot.Metrics.ContainsKey(key))
            {
                continue;
            }

            yield return new JsonMetricRow(
                gpu.Id.Value,
                MetricCatalog.GpuUtilization.Value,
                null,
                "percent",
                snapshot.CapturedAt,
                "none",
                "unknown",
                "unsupported",
                "notApplicable");
        }
    }

    private static JsonMetricRow ToMetricRow(MetricObservation observation) => new(
        observation.DeviceId.Value,
        observation.MetricId.Value,
        observation.Value,
        Camel(observation.Unit.ToString()),
        observation.ObservedAt,
        observation.ProviderId.Value,
        Camel(observation.Quality.ToString()),
        Camel(observation.Availability.ToString()),
        Camel(observation.Freshness.ToString()));

    private static string Camel(string value) =>
        string.IsNullOrEmpty(value) ? value : char.ToLowerInvariant(value[0]) + value[1..];
}
