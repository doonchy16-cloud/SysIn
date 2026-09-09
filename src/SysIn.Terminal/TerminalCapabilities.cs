namespace SysIn.Terminal;

public sealed record TerminalCapabilities(
    bool Interactive,
    bool TrueColor,
    bool Unicode,
    bool Mouse,
    bool AlternateScreen,
    bool CursorAddressing)
{
    public static readonly TerminalCapabilities Premium = new(true, true, true, true, true, true);
}
