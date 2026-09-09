using System.Text;

namespace SysIn.Terminal;

public sealed class FrameBuffer
{
    private readonly Cell[] cells;

    public int Width { get; }
    public int Height { get; }

    public FrameBuffer(int width, int height)
    {
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        Width = width;
        Height = height;
        cells = new Cell[checked(width * height)];
        Clear();
    }

    public void Clear() => Array.Fill(cells, Cell.Empty);

    public void Clear(Cell cell) => Array.Fill(cells, cell);

    public void Set(int x, int y, Cell cell)
    {
        cells[IndexOf(x, y)] = cell;
    }

    public Cell Get(int x, int y) => cells[IndexOf(x, y)];

    public void WriteText(
        string text,
        int x,
        int y,
        Rgb24 foreground,
        Rgb24 background,
        bool clip)
    {
        ArgumentNullException.ThrowIfNull(text);
        ValidateCoordinate(x, y);

        var available = Width - x;
        if (!clip && text.Length > available)
        {
            throw new ArgumentOutOfRangeException(nameof(text), "Text exceeds the frame width and clipping was not requested.");
        }

        var length = clip ? Math.Min(text.Length, available) : text.Length;
        for (var offset = 0; offset < length; offset++)
        {
            Set(x + offset, y, new Cell(text[offset], foreground, background));
        }
    }

    public string ToPlainText()
    {
        var builder = new StringBuilder((Width + Environment.NewLine.Length) * Height);
        for (var y = 0; y < Height; y++)
        {
            if (y > 0)
            {
                builder.AppendLine();
            }

            for (var x = 0; x < Width; x++)
            {
                builder.Append(Get(x, y).Glyph);
            }
        }

        return builder.ToString();
    }

    private int IndexOf(int x, int y)
    {
        ValidateCoordinate(x, y);
        return checked((y * Width) + x);
    }

    private void ValidateCoordinate(int x, int y)
    {
        if ((uint)x >= (uint)Width)
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }

        if ((uint)y >= (uint)Height)
        {
            throw new ArgumentOutOfRangeException(nameof(y));
        }
    }
}
