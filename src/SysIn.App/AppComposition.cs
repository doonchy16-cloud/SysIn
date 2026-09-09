using SysIn.Platform.Windows;
using SysIn.Providers;
using SysIn.Telemetry;

namespace SysIn.App;

public sealed record WindowsPreviewComposition(
    TelemetryStore Store,
    CollectorScheduler Scheduler);

public static class AppComposition
{
    public static async ValueTask<WindowsPreviewComposition> CreateWindowsPreviewAsync(CancellationToken cancellationToken)
    {
        var provider = new WindowsProvider(TimeProvider.System);
        var devices = await provider.DiscoverAsync(cancellationToken).ConfigureAwait(false);
        var store = new TelemetryStore(new FreshnessPolicy());
        store.RegisterDevices(devices);
        var collectors = provider.CreateCollectors(devices);
        var supervisor = new CollectorSupervisor(TimeProvider.System);
        var scheduler = new CollectorScheduler(
            collectors,
            supervisor,
            store,
            new SystemCollectorDelay(),
            cancellationToken);
        scheduler.Start();
        return new WindowsPreviewComposition(store, scheduler);
    }

    public static async ValueTask<SystemSnapshot> CaptureWindowsSnapshotAsync(
        TimeSpan warmup,
        CancellationToken cancellationToken)
    {
        var composition = await CreateWindowsPreviewAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await Task.Delay(warmup, cancellationToken).ConfigureAwait(false);
            return composition.Store.BuildSnapshot(TimeProvider.System.GetUtcNow());
        }
        finally
        {
            await composition.Scheduler.DisposeAsync().ConfigureAwait(false);
        }
    }
}
