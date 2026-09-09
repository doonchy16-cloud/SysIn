using SysIn.Terminal;
using SysIn.Views;

namespace SysIn.Native.Tests;

public sealed class RenderCaptureTests
{
    public static TheoryData<int, int> CaptureSizes => new()
    {
        { 80, 24 },
        { 100, 30 },
        { 120, 35 },
        { 140, 40 },
        { 160, 45 },
        { 180, 50 },
        { 200, 60 }
    };

    [Theory]
    [MemberData(nameof(CaptureSizes))]
    public void Overview_capture_is_written_for_certification_review(int width, int height)
    {
        var frame = new FrameBuffer(width, height);
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20, TimeSpan.FromMilliseconds(3.2)));

        new OverviewRenderer().Render(
            model,
            frame,
            SpectrumTheme.Default,
            ResponsiveLayout.Select(width, height));

        var text = frame.ToPlainText();
        var root = TestFixtures.RepositoryRoot();
        var captureDirectory = Path.Combine(root, "artifacts", "render-captures");
        Directory.CreateDirectory(captureDirectory);
        var path = Path.Combine(captureDirectory, $"overview-{width}x{height}.txt");
        File.WriteAllText(path, text);

        Assert.True(File.Exists(path));
        Assert.Contains("SYSIN", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Intel Iris Xe", text, StringComparison.Ordinal);
        Assert.Contains("NVIDIA GeForce RTX Test", text, StringComparison.Ordinal);
        Assert.Contains("N/A", text, StringComparison.Ordinal);
    }
}
