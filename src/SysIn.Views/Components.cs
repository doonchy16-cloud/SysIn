using SysIn.Terminal;

namespace SysIn.Views;

internal static class Components
{
    public static void Fill(FrameBuffer frame, int x, int y, int width, int height, Rgb24 background)
    {
        var cell = new Cell(' ', SpectrumTheme.Default.TextPrimary, background);
        for (var row = y; row < y + height && row < frame.Height; row++)
        {
            for (var column = x; column < x + width && column < frame.Width; column++)
            {
                if (column >= 0 && row >= 0)
                {
                    frame.Set(column, row, cell);
                }
            }
        }
    }

    public static void Panel(
        FrameBuffer frame,
        int x,
        int y,
        int width,
        int height,
        string title,
        Rgb24 accent,
        Rgb24 surface,
        Rgb24 text)
    {
        if (width < 4 || height < 3 || x < 0 || y < 0 || x + width > frame.Width || y + height > frame.Height)
        {
            return;
        }

        Fill(frame, x, y, width, height, surface);
        for (var row = y; row < y + height; row++)
        {
            frame.Set(x, row, new Cell('│', accent, surface));
        }

        frame.WriteText($" {title} ", x + 2, y, accent, surface, clip: true);
        for (var column = x + 1; column < x + width; column++)
        {
            frame.Set(column, y + height - 1, new Cell('─', accent, surface));
        }

        frame.Set(x, y + height - 1, new Cell('└', accent, surface));
        if (x + width - 1 < frame.Width)
        {
            frame.Set(x + width - 1, y + height - 1, new Cell('┘', accent, surface));
        }
    }

    public static void LabelValue(
        FrameBuffer frame,
        int x,
        int y,
        int maxWidth,
        string label,
        string value,
        Rgb24 labelColor,
        Rgb24 valueColor,
        Rgb24 background)
    {
        if (maxWidth <= 0 || x >= frame.Width || y >= frame.Height)
        {
            return;
        }

        frame.WriteText(label, x, y, labelColor, background, clip: true);
        var valueX = Math.Min(frame.Width - 1, x + Math.Max(1, maxWidth - value.Length));
        frame.WriteText(value, valueX, y, valueColor, background, clip: true);
    }
}
