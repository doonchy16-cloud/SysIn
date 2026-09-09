using System.Collections.Concurrent;

namespace SysIn.Terminal;

public sealed class VirtualTerminalHost : ITerminalHost
{
    private readonly ConcurrentQueue<ConsoleKeyInfo> keys = new();
    private readonly Cell[] cells;

    public int Width { get; }
    public int Height { get; }
    public TerminalCapabilities Capabilities { get; }
    public int EnterCount { get; private set; }
    public int RestoreCount { get; private set; }

    public VirtualTerminalHost(int width, int height, TerminalCapabilities capabilities)
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
        Capabilities = capabilities ?? throw new ArgumentNullException(nameof(capabilities));
        cells = new Cell[checked(width * height)];
        Array.Fill(cells, Cell.Empty);
    }

    public ValueTask EnterInteractiveAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        EnterCount++;
        return ValueTask.CompletedTask;
    }

    public ValueTask ApplyAsync(IReadOnlyList<FrameChange> changes, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(changes);
        cancellationToken.ThrowIfCancellationRequested();

        foreach (var change in changes)
        {
            if ((uint)change.X >= (uint)Width || (uint)change.Y >= (uint)Height)
            {
                throw new ArgumentOutOfRangeException(nameof(changes), "A frame change was outside terminal bounds.");
            }

            cells[(change.Y * Width) + change.X] = change.Cell;
        }

        return ValueTask.CompletedTask;
    }

    public bool TryReadKey(out ConsoleKeyInfo key) => keys.TryDequeue(out key);

    public ValueTask RestoreAsync(CancellationToken cancellationToken)
    {
        RestoreCount++;
        return ValueTask.CompletedTask;
    }

    public void QueueKey(ConsoleKeyInfo key) => keys.Enqueue(key);

    public Cell GetCell(int x, int y)
    {
        if ((uint)x >= (uint)Width)
        {
            throw new ArgumentOutOfRangeException(nameof(x));
        }

        if ((uint)y >= (uint)Height)
        {
            throw new ArgumentOutOfRangeException(nameof(y));
        }

        return cells[(y * Width) + x];
    }
}
