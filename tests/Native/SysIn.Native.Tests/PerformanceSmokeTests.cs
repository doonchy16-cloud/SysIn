using System.Diagnostics;
using SysIn.Terminal;
using SysIn.Views;

namespace SysIn.Native.Tests;

public sealed class PerformanceSmokeTests
{
    [Fact]
    public void Overview_render_and_diff_mean_is_under_ten_milliseconds()
    {
        const int iterations = 200;
        const int width = 160;
        const int height = 45;

        var snapshot = TestFixtures.DualGpuSnapshot();
        var renderer = new OverviewRenderer();
        var theme = SpectrumTheme.Default;
        var mode = ResponsiveLayout.Select(width, height);
        var previous = new FrameBuffer(width, height);
        var stopwatch = Stopwatch.StartNew();

        for (var index = 0; index < iterations; index++)
        {
            var frame = new FrameBuffer(width, height);
            var actualFps = index % 2 == 0 ? 19.8 : 19.9;
            var model = OverviewViewModel.FromSnapshot(
                snapshot,
                new RenderStats(actualFps, 20, TimeSpan.FromMilliseconds(3.2)));

            renderer.Render(model, frame, theme, mode);
            _ = FrameDiff.Compute(previous, frame);
            previous = frame;
        }

        stopwatch.Stop();
        var meanMilliseconds = stopwatch.Elapsed.TotalMilliseconds / iterations;
        Console.WriteLine($"Mean render+diff: {meanMilliseconds:F3} ms across {iterations} frames.");

        Assert.True(
            meanMilliseconds < 10,
            $"Mean render+diff was {meanMilliseconds:F3} ms; smoke budget is <10 ms.");
    }
}
