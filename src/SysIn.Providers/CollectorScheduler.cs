using SysIn.Telemetry;

namespace SysIn.Providers;

public interface ICollectorDelay
{
    ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken);
}

public sealed class CollectorScheduler : IAsyncDisposable
{
    private readonly IReadOnlyList<ITelemetryCollector> collectors;
    private readonly CollectorSupervisor supervisor;
    private readonly TelemetryStore store;
    private readonly ICollectorDelay delay;
    private readonly CancellationTokenSource cancellation;
    private readonly object startGate = new();
    private Task[] tasks = [];
    private int started;
    private int paused;

    public CollectorScheduler(
        IReadOnlyList<ITelemetryCollector> collectors,
        CollectorSupervisor supervisor,
        TelemetryStore store,
        ICollectorDelay delay,
        CancellationToken appToken)
    {
        this.collectors = collectors ?? throw new ArgumentNullException(nameof(collectors));
        this.supervisor = supervisor ?? throw new ArgumentNullException(nameof(supervisor));
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.delay = delay ?? throw new ArgumentNullException(nameof(delay));
        cancellation = CancellationTokenSource.CreateLinkedTokenSource(appToken);
    }

    public bool IsPaused => Volatile.Read(ref paused) != 0;

    public void Start()
    {
        lock (startGate)
        {
            if (Interlocked.Exchange(ref started, 1) != 0)
            {
                throw new InvalidOperationException("CollectorScheduler has already been started.");
            }

            tasks = collectors
                .Select(collector => Task.Run(() => RunCollectorAsync(collector, cancellation.Token)))
                .ToArray();
        }
    }

    public void SetPaused(bool value) =>
        Interlocked.Exchange(ref paused, value ? 1 : 0);

    public async ValueTask DisposeAsync()
    {
        cancellation.Cancel();
        try
        {
            await Task.WhenAll(tasks).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
        }
        finally
        {
            cancellation.Dispose();
        }
    }

    private async Task RunCollectorAsync(ITelemetryCollector collector, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                if (IsPaused)
                {
                    await delay.DelayAsync(TimeSpan.FromMilliseconds(50), cancellationToken).ConfigureAwait(false);
                    continue;
                }

                await supervisor.RunOnceAsync(collector, store, cancellationToken).ConfigureAwait(false);
                await delay.DelayAsync(collector.Cadence, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
        }
    }
}
