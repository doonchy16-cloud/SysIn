namespace SysIn.Terminal;

public interface ITerminalHost
{
    int Width { get; }
    int Height { get; }
    TerminalCapabilities Capabilities { get; }

    ValueTask EnterInteractiveAsync(CancellationToken cancellationToken);
    ValueTask ApplyAsync(IReadOnlyList<FrameChange> changes, CancellationToken cancellationToken);
    bool TryReadKey(out ConsoleKeyInfo key);
    ValueTask RestoreAsync(CancellationToken cancellationToken);
}
