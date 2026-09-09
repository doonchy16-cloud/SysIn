using SysIn.Terminal;
using SysIn.Views;

namespace SysIn.Native.Tests;

public sealed class OverviewRendererTests
{
    [Theory]
    [InlineData(200, 60)]
    [InlineData(160, 45)]
    [InlineData(120, 35)]
    [InlineData(80, 24)]
    public void Overview_renders_required_information_without_bounds_errors(int width, int height)
    {
        var frame = new FrameBuffer(width, height);
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20.0, TimeSpan.FromMilliseconds(4)));

        new OverviewRenderer().Render(model, frame, SpectrumTheme.Default, ResponsiveLayout.Select(width, height));
        var text = frame.ToPlainText();

        Assert.Contains("Intel Iris Xe", text, StringComparison.Ordinal);
        Assert.Contains("NVIDIA GeForce RTX Test", text, StringComparison.Ordinal);
        Assert.Contains("N/A", text, StringComparison.Ordinal);
        Assert.Contains("19.8/20", text, StringComparison.Ordinal);
    }

    [Fact]
    public void Medium_overview_keeps_the_Quit_command_complete_at_100x30()
    {
        var frame = new FrameBuffer(100, 30);
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20.0, TimeSpan.FromMilliseconds(4)));

        new OverviewRenderer().Render(
            model,
            frame,
            SpectrumTheme.Default,
            ResponsiveLayout.Select(frame.Width, frame.Height));

        var footer = frame.ToPlainText().Split(Environment.NewLine)[^1];
        Assert.Contains("[Q] Quit", footer, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(80, 24)]
    [InlineData(160, 45)]
    public void Preview_command_bar_advertises_only_keys_implemented_by_the_live_loop(int width, int height)
    {
        var frame = new FrameBuffer(width, height);
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20.0, TimeSpan.FromMilliseconds(4)));

        new OverviewRenderer().Render(
            model,
            frame,
            SpectrumTheme.Default,
            ResponsiveLayout.Select(frame.Width, frame.Height));

        var footer = frame.ToPlainText().Split(Environment.NewLine)[^1];
        Assert.Contains("[P] Pause", footer, StringComparison.Ordinal);
        Assert.Contains("[F] FPS", footer, StringComparison.Ordinal);
        Assert.Contains("[Q] Quit", footer, StringComparison.Ordinal);
        Assert.DoesNotContain("[2]", footer, StringComparison.Ordinal);
        Assert.DoesNotContain("[/]", footer, StringComparison.Ordinal);
        Assert.DoesNotContain("[?]", footer, StringComparison.Ordinal);
    }

    [Fact]
    public void Large_overview_keeps_GPU_stack_out_of_lower_card_body()
    {
        var frame = new FrameBuffer(160, 45);
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20.0, TimeSpan.FromMilliseconds(4)));

        new OverviewRenderer().Render(model, frame, SpectrumTheme.Default, LayoutMode.Large);

        var lines = frame.ToPlainText().Split(Environment.NewLine);
        var lowerCardBodyRow = lines[30];
        Assert.DoesNotContain('─', lowerCardBodyRow);
    }

    [Fact]
    public void Large_overview_uses_the_available_terminal_instead_of_forming_a_top_left_island()
    {
        var frame = new FrameBuffer(160, 45);
        var theme = SpectrumTheme.Default;
        var model = OverviewViewModel.FromSnapshot(
            TestFixtures.DualGpuSnapshot(),
            new RenderStats(19.8, 20.0, TimeSpan.FromMilliseconds(4)));

        new OverviewRenderer().Render(model, frame, theme, LayoutMode.Large);

        var points = new List<(int X, int Y)>();
        for (var y = 0; y < frame.Height; y++)
        {
            for (var x = 0; x < frame.Width; x++)
            {
                var cell = frame.Get(x, y);
                if (cell.Background != theme.Background || cell.Glyph != ' ')
                {
                    points.Add((x, y));
                }
            }
        }

        Assert.NotEmpty(points);
        Assert.True(points.Max(point => point.X) >= 130, $"right={points.Max(point => point.X)}");
        Assert.True(points.Max(point => point.Y) >= 38, $"bottom={points.Max(point => point.Y)}");
    }
}
