using System.Text.Json;
using SysIn.Cli;

namespace SysIn.Native.Tests;

public sealed class CliContractTests
{
    [Fact]
    public void No_args_defaults_to_overview()
    {
        var parsed = CommandParser.Parse([]);

        Assert.Equal(NativeCommand.Overview, parsed.Command);
        Assert.False(parsed.Json);
        Assert.Null(parsed.Error);
    }

    [Theory]
    [InlineData("overview", NativeCommand.Overview)]
    [InlineData("snapshot", NativeCommand.Snapshot)]
    [InlineData("version", NativeCommand.Version)]
    [InlineData("doctor", NativeCommand.Doctor)]
    [InlineData("help", NativeCommand.Help)]
    public void Authorized_commands_parse_exactly(string token, NativeCommand expected)
    {
        var parsed = CommandParser.Parse([token]);

        Assert.Equal(expected, parsed.Command);
        Assert.False(parsed.Json);
        Assert.Null(parsed.Error);
    }

    [Fact]
    public void Snapshot_json_is_authorized()
    {
        var parsed = CommandParser.Parse(["snapshot", "--json"]);

        Assert.Equal(NativeCommand.Snapshot, parsed.Command);
        Assert.True(parsed.Json);
        Assert.Null(parsed.Error);
    }

    [Fact]
    public void Near_miss_command_is_invalid_and_suggests_canonical_command()
    {
        var parsed = CommandParser.Parse(["versoin"]);

        Assert.Equal(NativeCommand.Invalid, parsed.Command);
        Assert.NotNull(parsed.Error);
        Assert.Contains("version", parsed.Error, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Snapshot_json_materializes_missing_gpu_usage_as_unsupported_null()
    {
        var json = SnapshotJsonFormatter.Format(TestFixtures.DualGpuSnapshot());
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        Assert.Equal("1.0-preview", root.GetProperty("schemaVersion").GetString());

        var gpuIds = root.GetProperty("devices")
            .EnumerateArray()
            .Where(device => string.Equals(device.GetProperty("kind").GetString(), "gpu", StringComparison.Ordinal))
            .Select(device => device.GetProperty("id").GetString())
            .ToArray();

        Assert.Equal(2, gpuIds.Length);

        var metrics = root.GetProperty("metrics").EnumerateArray().ToArray();
        foreach (var gpuId in gpuIds)
        {
            var usage = Assert.Single(
                metrics,
                metric => string.Equals(metric.GetProperty("deviceId").GetString(), gpuId, StringComparison.Ordinal)
                    && string.Equals(metric.GetProperty("metricId").GetString(), "gpu.utilization", StringComparison.Ordinal));

            Assert.Equal("unsupported", usage.GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, usage.GetProperty("value").ValueKind);
        }
    }
}
