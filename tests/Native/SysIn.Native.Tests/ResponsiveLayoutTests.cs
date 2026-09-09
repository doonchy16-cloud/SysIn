using SysIn.Terminal;

namespace SysIn.Native.Tests;

public sealed class ResponsiveLayoutTests
{
    [Theory]
    [InlineData(200, 60, LayoutMode.Xl)]
    [InlineData(160, 45, LayoutMode.Large)]
    [InlineData(120, 35, LayoutMode.Medium)]
    [InlineData(80, 24, LayoutMode.Compact)]
    [InlineData(79, 24, LayoutMode.MinimumSafe)]
    [InlineData(100, 23, LayoutMode.MinimumSafe)]
    public void Layout_mode_is_deterministic(int width, int height, LayoutMode expected)
    {
        Assert.Equal(expected, ResponsiveLayout.Select(width, height));
    }

    [Fact]
    public void Spectrum_exposes_semantic_subsystem_palettes()
    {
        var theme = SpectrumTheme.Default;

        Assert.Equal(new Rgb24(0x15, 0x5E, 0xEF), theme.Cpu.Deep);
        Assert.Equal(new Rgb24(0x10, 0xB9, 0x81), theme.Gpu.Deep);
        Assert.Equal(new Rgb24(0x7C, 0x3A, 0xED), theme.Memory.Deep);
        Assert.Equal(new Rgb24(0xF5, 0x9E, 0x0B), theme.Storage.Deep);
        Assert.Equal(new Rgb24(0x06, 0xB6, 0xD4), theme.Network.Deep);
        Assert.Equal(new Rgb24(0xEA, 0xB3, 0x08), theme.Processes.Deep);
        Assert.Equal(new Rgb24(0xEF, 0x44, 0x44), theme.Critical);
    }
}
