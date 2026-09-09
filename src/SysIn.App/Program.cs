using SysIn.App;
using SysIn.Cli;
using SysIn.Terminal;
using SysIn.Views;

if (!OperatingSystem.IsWindows())
{
    Console.Error.WriteLine("SysIn 1.2 Preview currently supports Windows only.");
    return 69;
}

var parsed = CommandParser.Parse(args);
if (parsed.Command == NativeCommand.Invalid)
{
    Console.Error.WriteLine(parsed.Error ?? "Invalid command.");
    Console.Error.WriteLine("Use 'sysin help' for Preview commands.");
    return 2;
}

using var cancellation = new CancellationTokenSource();
ConsoleCancelEventHandler handler = (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};
Console.CancelKeyPress += handler;

try
{
    return parsed.Command switch
    {
        NativeCommand.Overview => await RunOverviewAsync(cancellation.Token),
        NativeCommand.Snapshot => await RunSnapshotAsync(parsed.Json, cancellation.Token),
        NativeCommand.Version => WriteVersion(),
        NativeCommand.Doctor => await RunDoctorAsync(cancellation.Token),
        NativeCommand.Help => WriteHelp(),
        _ => 2
    };
}
catch (OperationCanceledException)
{
    return 130;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"SysIn Preview failed: {exception.GetType().Name}");
    return 1;
}
finally
{
    Console.CancelKeyPress -= handler;
}

static int WriteVersion()
{
    Console.WriteLine("SysIn 1.2.0-preview.1");
    Console.WriteLine("Channel: Preview");
    Console.WriteLine("Runtime: Native .NET 10");
    Console.WriteLine("Platform: win-x64");
    return 0;
}

static int WriteHelp()
{
    Console.WriteLine("SysIn 1.2 Preview");
    Console.WriteLine();
    Console.WriteLine("Usage:");
    Console.WriteLine("  sysin                 Open the interactive Overview");
    Console.WriteLine("  sysin overview        Open the interactive Overview");
    Console.WriteLine("  sysin snapshot        Print a human-readable telemetry snapshot");
    Console.WriteLine("  sysin snapshot --json Print schema 1.0-preview JSON");
    Console.WriteLine("  sysin doctor          Run bounded Preview diagnostics");
    Console.WriteLine("  sysin version         Print Preview version identity");
    Console.WriteLine("  sysin help            Show this help");
    Console.WriteLine();
    Console.WriteLine("Overview keys: Q/Esc quit | P pause collection | F cycle 20/10/5/1 FPS");
    return 0;
}

static async Task<int> RunSnapshotAsync(bool json, CancellationToken cancellationToken)
{
    var snapshot = await AppComposition.CaptureWindowsSnapshotAsync(
        TimeSpan.FromMilliseconds(350),
        cancellationToken);

    Console.WriteLine(json
        ? SnapshotJsonFormatter.Format(snapshot)
        : TextSnapshotFormatter.Format(snapshot));
    return 0;
}

static async Task<int> RunDoctorAsync(CancellationToken cancellationToken)
{
    var terminal = new AnsiTerminalHost();
    var snapshot = await AppComposition.CaptureWindowsSnapshotAsync(
        TimeSpan.FromMilliseconds(350),
        cancellationToken);

    Console.WriteLine("SysIn Doctor — Preview scope");
    Console.WriteLine($"Runtime: PASS — .NET {Environment.Version.Major}");
    Console.WriteLine($"Windows discovery: PASS — {snapshot.Devices.Count} devices visible");

    var unhealthy = snapshot.CollectorHealth.Values
        .Where(health => health.State != SysIn.Core.CollectorState.Healthy)
        .OrderBy(health => health.Id.Value, StringComparer.Ordinal)
        .ToArray();
    Console.WriteLine(unhealthy.Length == 0
        ? $"Collectors: PASS — {snapshot.CollectorHealth.Count} reporting healthy"
        : $"Collectors: DEGRADED — {unhealthy.Length} collector(s) not healthy");
    foreach (var health in unhealthy)
    {
        Console.WriteLine($"  {health.Id.Value}: {health.State} ({health.LastErrorClass ?? "no error class"})");
    }

    var capabilities = terminal.Capabilities;
    var tier = !capabilities.Interactive
        ? "Tier0 noninteractive"
        : capabilities.TrueColor && capabilities.CursorAddressing && capabilities.AlternateScreen
            ? "Tier3 premium"
            : "Tier2 VT-compatible";
    Console.WriteLine($"Terminal: {tier}");
    Console.WriteLine("Renderer: Preview Overview registered; live visual certification is separate.");
    Console.WriteLine("Scope: runtime, Windows discovery, collector health, terminal capability, renderer registration.");
    return unhealthy.Length == 0 ? 0 : 1;
}

static async Task<int> RunOverviewAsync(CancellationToken cancellationToken)
{
    var terminal = new AnsiTerminalHost();
    if (!terminal.Capabilities.Interactive)
    {
        Console.Error.WriteLine("Interactive Overview requires an attached terminal. Use 'sysin snapshot' or 'sysin snapshot --json'.");
        return 2;
    }

    var composition = await AppComposition.CreateWindowsPreviewAsync(cancellationToken);
    try
    {
        var renderer = new OverviewRenderer();
        var loop = new InteractiveLoop(
            terminal,
            () => composition.Store.BuildSnapshot(TimeProvider.System.GetUtcNow()),
            OverviewViewModel.FromSnapshot,
            renderer,
            SpectrumTheme.Default,
            TimeProvider.System,
            new SystemDelayScheduler(),
            () => composition.Scheduler.SetPaused(!composition.Scheduler.IsPaused),
            () => composition.Scheduler.IsPaused,
            20);

        await loop.RunAsync(cancellationToken);
        return 0;
    }
    finally
    {
        await composition.Scheduler.DisposeAsync();
    }
}
