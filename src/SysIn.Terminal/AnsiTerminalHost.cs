using System.Runtime.InteropServices;
using System.Text;

namespace SysIn.Terminal;

public sealed class AnsiTerminalHost : ITerminalHost
{
    private const int StdOutputHandle = -11;
    private const uint EnableVirtualTerminalProcessing = 0x0004;
    private readonly nint outputHandle;
    private uint originalConsoleMode;
    private bool consoleModeChanged;
    private bool entered;

    public AnsiTerminalHost()
    {
        Capabilities = DetectCapabilities();
        outputHandle = OperatingSystem.IsWindows() ? GetStdHandle(StdOutputHandle) : 0;
    }

    public int Width => SafeDimension(static () => Console.WindowWidth, 80);
    public int Height => SafeDimension(static () => Console.WindowHeight, 24);
    public TerminalCapabilities Capabilities { get; }

    public ValueTask EnterInteractiveAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Capabilities.Interactive || entered)
        {
            return ValueTask.CompletedTask;
        }

        if (OperatingSystem.IsWindows() && outputHandle != 0 && GetConsoleMode(outputHandle, out var mode) != 0)
        {
            originalConsoleMode = mode;
            var requested = mode | EnableVirtualTerminalProcessing;
            if (requested != mode && SetConsoleMode(outputHandle, requested) != 0)
            {
                consoleModeChanged = true;
            }
        }

        Console.OutputEncoding = Encoding.UTF8;
        if (Capabilities.AlternateScreen)
        {
            Console.Out.Write("\u001b[?1049h");
        }

        Console.Out.Write("\u001b[?25l\u001b[0m");
        Console.Out.Flush();
        entered = true;
        return ValueTask.CompletedTask;
    }

    public ValueTask ApplyAsync(IReadOnlyList<FrameChange> changes, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(changes);
        cancellationToken.ThrowIfCancellationRequested();
        if (!Capabilities.Interactive || changes.Count == 0)
        {
            return ValueTask.CompletedTask;
        }

        var output = new StringBuilder(changes.Count * 32);
        foreach (var change in changes)
        {
            var foreground = change.Cell.Foreground;
            var background = change.Cell.Background;
            output.Append("\u001b[").Append(change.Y + 1).Append(';').Append(change.X + 1).Append('H');
            output.Append("\u001b[38;2;").Append(foreground.R).Append(';').Append(foreground.G).Append(';').Append(foreground.B).Append('m');
            output.Append("\u001b[48;2;").Append(background.R).Append(';').Append(background.G).Append(';').Append(background.B).Append('m');
            output.Append(change.Cell.Glyph);
        }

        Console.Out.Write(output.ToString());
        Console.Out.Flush();
        return ValueTask.CompletedTask;
    }

    public bool TryReadKey(out ConsoleKeyInfo key)
    {
        key = default;
        if (!Capabilities.Interactive)
        {
            return false;
        }

        try
        {
            if (!Console.KeyAvailable)
            {
                return false;
            }

            key = Console.ReadKey(intercept: true);
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public ValueTask RestoreAsync(CancellationToken cancellationToken)
    {
        if (entered)
        {
            Console.Out.Write("\u001b[0m\u001b[?25h\u001b[?1000l\u001b[?1006l");
            if (Capabilities.AlternateScreen)
            {
                Console.Out.Write("\u001b[?1049l");
            }

            Console.Out.Flush();
            entered = false;
        }

        if (OperatingSystem.IsWindows() && consoleModeChanged && outputHandle != 0)
        {
            _ = SetConsoleMode(outputHandle, originalConsoleMode);
            consoleModeChanged = false;
        }

        return ValueTask.CompletedTask;
    }

    private static TerminalCapabilities DetectCapabilities()
    {
        var interactive = !Console.IsOutputRedirected && !Console.IsInputRedirected;
        return new TerminalCapabilities(
            interactive,
            TrueColor: interactive,
            Unicode: interactive,
            Mouse: false,
            AlternateScreen: interactive,
            CursorAddressing: interactive);
    }

    private static int SafeDimension(Func<int> reader, int fallback)
    {
        try
        {
            return Math.Max(1, reader());
        }
        catch (IOException)
        {
            return fallback;
        }
        catch (PlatformNotSupportedException)
        {
            return fallback;
        }
    }

#pragma warning disable SYSLIB1054
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint GetStdHandle(int standardHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern int GetConsoleMode(nint consoleHandle, out uint mode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern int SetConsoleMode(nint consoleHandle, uint mode);
#pragma warning restore SYSLIB1054
}
