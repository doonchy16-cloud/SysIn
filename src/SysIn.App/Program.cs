using SysIn.App;
using SysIn.Terminal;
using SysIn.Views;

if (!OperatingSystem.IsWindows())
{
    Console.Error.WriteLine("SysIn 1.2 preview currently supports Windows x64 only.");
    return 69;
}

if (args.Length > 0 && !string.Equals(args[0], "overview", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("This preview step currently accepts only: overview");
    return 2;
}

using var cancellation = new CancellationTokenSource();
ConsoleCancelEventHandler handler = (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};
Console.CancelKeyPress += handler;

var composition = await AppComposition.CreateWindowsPreviewAsync(cancellation.Token);
try
{
    var terminal = new AnsiTerminalHost();
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

    await loop.RunAsync(cancellation.Token);
    return 0;
}
finally
{
    Console.CancelKeyPress -= handler;
    await composition.Scheduler.DisposeAsync();
}
