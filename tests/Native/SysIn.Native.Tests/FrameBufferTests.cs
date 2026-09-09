using SysIn.Terminal;

namespace SysIn.Native.Tests;

public sealed class FrameBufferTests
{
    [Fact]
    public void Diff_contains_only_changed_cells()
    {
        var before = new FrameBuffer(4, 2);
        var after = new FrameBuffer(4, 2);
        after.Set(2, 1, new Cell('X', Rgb24.White, Rgb24.Black));

        var changes = FrameDiff.Compute(before, after);

        Assert.Single(changes);
        Assert.Equal((2, 1), (changes[0].X, changes[0].Y));
        Assert.Equal('X', changes[0].Cell.Glyph);
    }

    [Fact]
    public void Write_at_width_is_rejected()
    {
        var frame = new FrameBuffer(80, 24);
        Assert.Throws<ArgumentOutOfRangeException>(() => frame.Set(80, 0, Cell.Empty));
    }

    [Fact]
    public void WriteText_can_clip_but_never_silently_overflow()
    {
        var frame = new FrameBuffer(5, 2);
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            frame.WriteText("abcdef", 0, 0, Rgb24.White, Rgb24.Black, clip: false));

        frame.WriteText("abcdef", 0, 1, Rgb24.White, Rgb24.Black, clip: true);
        Assert.Contains("abcde", frame.ToPlainText(), StringComparison.Ordinal);
    }

    [Fact]
    public void Diff_requires_equal_dimensions()
    {
        Assert.Throws<ArgumentException>(() =>
            FrameDiff.Compute(new FrameBuffer(4, 2), new FrameBuffer(5, 2)));
    }
}
