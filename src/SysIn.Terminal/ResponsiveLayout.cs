namespace SysIn.Terminal;

public enum LayoutMode
{
    Xl,
    Large,
    Medium,
    Compact,
    MinimumSafe
}

public static class ResponsiveLayout
{
    public static LayoutMode Select(int width, int height)
    {
        if (width >= 180 && height >= 45)
        {
            return LayoutMode.Xl;
        }

        if (width >= 140 && height >= 35)
        {
            return LayoutMode.Large;
        }

        if (width >= 100 && height >= 30)
        {
            return LayoutMode.Medium;
        }

        if (width >= 80 && height >= 24)
        {
            return LayoutMode.Compact;
        }

        return LayoutMode.MinimumSafe;
    }
}
