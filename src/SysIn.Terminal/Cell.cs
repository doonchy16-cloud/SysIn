namespace SysIn.Terminal;

public readonly record struct Rgb24(byte R, byte G, byte B)
{
    public static readonly Rgb24 White = new(248, 250, 252);
    public static readonly Rgb24 Black = new(7, 17, 31);
}

public readonly record struct Cell(char Glyph, Rgb24 Foreground, Rgb24 Background)
{
    public static readonly Cell Empty = new(' ', Rgb24.White, Rgb24.Black);
}
