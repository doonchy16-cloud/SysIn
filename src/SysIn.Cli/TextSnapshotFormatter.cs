using System.Globalization;
using System.Text;
using SysIn.Core;
using SysIn.Telemetry;

namespace SysIn.Cli;

public static class TextSnapshotFormatter
{
    public static string Format(SystemSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        var builder = new StringBuilder();
        builder.AppendLine($"SysIn Snapshot — {snapshot.CapturedAt:O}");
        builder.AppendLine($"Devices: {snapshot.Devices.Count} | Metrics: {snapshot.Metrics.Count} | Collectors: {snapshot.CollectorHealth.Count}");
        builder.AppendLine();

        foreach (var device in snapshot.Devices.Values
                     .OrderBy(device => device.Kind)
                     .ThenBy(device => device.Name, StringComparer.Ordinal))
        {
            builder.AppendLine($"[{device.Kind}] {device.Name} ({device.Id.Value})");
            var metrics = snapshot.Metrics.Values
                .Where(metric => metric.DeviceId == device.Id)
                .OrderBy(metric => metric.MetricId.Value, StringComparer.Ordinal)
                .ToArray();

            foreach (var metric in metrics)
            {
                builder.Append("  ")
                    .Append(metric.MetricId.Value)
                    .Append(": ")
                    .Append(FormatMetric(metric))
                    .Append(" [")
                    .Append(metric.Availability)
                    .Append('/')
                    .Append(metric.Freshness)
                    .AppendLine("]");
            }

            if (device.Kind == DeviceKind.Gpu
                && !snapshot.Metrics.ContainsKey(new MetricKey(device.Id, MetricCatalog.GpuUtilization)))
            {
                builder.AppendLine("  gpu.utilization: N/A [Unsupported/NotApplicable]");
            }
        }

        if (snapshot.CollectorHealth.Count > 0)
        {
            builder.AppendLine();
            builder.AppendLine("Collector health:");
            foreach (var health in snapshot.CollectorHealth.Values.OrderBy(health => health.Id.Value, StringComparer.Ordinal))
            {
                builder.Append("  ")
                    .Append(health.Id.Value)
                    .Append(": ")
                    .Append(health.State)
                    .AppendLine();
            }
        }

        return builder.ToString().TrimEnd();
    }

    private static string FormatMetric(MetricObservation metric)
    {
        if (metric.Value is null)
        {
            return "N/A";
        }

        return metric.Unit switch
        {
            UnitId.Percent => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)}%",
            UnitId.Bytes => FormatBytes(metric.Value.Value),
            UnitId.BytesPerSecond => $"{FormatBytes(metric.Value.Value)}/s",
            UnitId.Seconds => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)} s",
            UnitId.Celsius => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)} °C",
            UnitId.Hertz => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)} Hz",
            UnitId.Watts => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)} W",
            UnitId.Rpm => $"{metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)} RPM",
            _ => metric.Value.Value.ToString("0.##", CultureInfo.InvariantCulture)
        };
    }

    private static string FormatBytes(double bytes)
    {
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        var value = Math.Max(0, bytes);
        var index = 0;
        while (value >= 1024 && index < units.Length - 1)
        {
            value /= 1024;
            index++;
        }

        return $"{value.ToString("0.##", CultureInfo.InvariantCulture)} {units[index]}";
    }
}
