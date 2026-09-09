namespace SysIn.Terminal;

public readonly record struct FrameChange(int X, int Y, Cell Cell);

public static class FrameDiff
{
    public static IReadOnlyList<FrameChange> Compute(FrameBuffer before, FrameBuffer after)
    {
        ArgumentNullException.ThrowIfNull(before);
        ArgumentNullException.ThrowIfNull(after);

        if (before.Width != after.Width || before.Height != after.Height)
        {
            throw new ArgumentException("Frame dimensions must match.", nameof(after));
        }

        var changes = new List<FrameChange>();
        for (var y = 0; y < after.Height; y++)
        {
            for (var x = 0; x < after.Width; x++)
            {
                var next = after.Get(x, y);
                if (before.Get(x, y) != next)
                {
                    changes.Add(new FrameChange(x, y, next));
                }
            }
        }

        return changes;
    }
}
