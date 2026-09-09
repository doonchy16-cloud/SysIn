using SysIn.Telemetry;
using SysIn.Terminal;
using SysIn.Views;

namespace SysIn.App;

public sealed class InteractiveLoop
{
    private readonly ITerminalHost terminal;
    private readonly Func<SystemSnapshot> snapshotFactory;
    private readonly Func<SystemSnapshot, RenderStats, OverviewViewModel> modelFactory;
    private readonly OverviewRenderer renderer;
    private readonly SpectrumTheme theme;
    private readonly TimeProvider timeProvider;
    private readonly IDelayScheduler delayScheduler;
    private readonly Action toggleCollectionPause;
    private readonly Func<bool> isCollectionPaused;
    private readonly int? maxFramesForTest;
    private double targetFps;

    public InteractiveLoop(
        ITerminalHost terminal,
        Func<SystemSnapshot> snapshotFactory,
        Func<SystemSnapshot, RenderStats, OverviewViewModel> modelFactory,
        OverviewRenderer renderer,
        SpectrumTheme theme,
        TimeProvider timeProvider,
        IDelayScheduler delayScheduler,
        Action toggleCollectionPause,
        Func<bool> isCollectionPaused,
        double targetFps,
        int? maxFramesForTest = null)
    {
        this.terminal = terminal ?? throw new ArgumentNullException(nameof(terminal));
        this.snapshotFactory = snapshotFactory ?? throw new ArgumentNullException(nameof(snapshotFactory));
        this.modelFactory = modelFactory ?? throw new ArgumentNullException(nameof(modelFactory));
        this.renderer = renderer ?? throw new ArgumentNullException(nameof(renderer));
        this.theme = theme ?? throw new ArgumentNullException(nameof(theme));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        this.delayScheduler = delayScheduler ?? throw new ArgumentNullException(nameof(delayScheduler));
        this.toggleCollectionPause = toggleCollectionPause ?? throw new ArgumentNullException(nameof(toggleCollectionPause));
        this.isCollectionPaused = isCollectionPaused ?? throw new ArgumentNullException(nameof(isCollectionPaused));
        if (targetFps <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(targetFps));
        }

        this.targetFps = targetFps;
        this.maxFramesForTest = maxFramesForTest;
    }

    public async ValueTask RunAsync(CancellationToken cancellationToken)
    {
        await terminal.EnterInteractiveAsync(cancellationToken).ConfigureAwait(false);
        FrameBuffer? previous = null;
        var frames = 0;
        var actualFps = targetFps;
        var lastFrameTime = TimeSpan.Zero;
        var lastFrameStarted = timeProvider.GetTimestamp();

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var frameStarted = timeProvider.GetTimestamp();
                var width = terminal.Width;
                var height = terminal.Height;
                if (previous is null || previous.Width != width || previous.Height != height)
                {
                    previous = new FrameBuffer(width, height);
                }

                var next = new FrameBuffer(width, height);
                var snapshot = snapshotFactory();
                var stats = new RenderStats(actualFps, targetFps, lastFrameTime);
                var model = modelFactory(snapshot, stats);
                renderer.Render(model, next, theme, ResponsiveLayout.Select(width, height));
                var changes = FrameDiff.Compute(previous, next);
                await terminal.ApplyAsync(changes, cancellationToken).ConfigureAwait(false);
                previous = next;
                frames++;

                while (terminal.TryReadKey(out var key))
                {
                    if (key.Key is ConsoleKey.Q or ConsoleKey.Escape)
                    {
                        return;
                    }

                    if (key.Key == ConsoleKey.P)
                    {
                        toggleCollectionPause();
                        _ = isCollectionPaused();
                    }
                    else if (key.Key == ConsoleKey.F)
                    {
                        targetFps = NextTarget(targetFps);
                    }
                }

                if (maxFramesForTest is { } maxFrames && frames >= maxFrames)
                {
                    break;
                }

                var frameElapsed = timeProvider.GetElapsedTime(frameStarted);
                var framePeriod = timeProvider.GetElapsedTime(lastFrameStarted, frameStarted);
                if (framePeriod > TimeSpan.Zero)
                {
                    actualFps = 1d / framePeriod.TotalSeconds;
                }
                lastFrameStarted = frameStarted;
                lastFrameTime = frameElapsed;

                var targetInterval = TimeSpan.FromSeconds(1d / targetFps);
                var remaining = targetInterval - frameElapsed;
                if (remaining <= TimeSpan.Zero)
                {
                    remaining = TimeSpan.FromMilliseconds(1);
                }

                await delayScheduler.DelayAsync(remaining, cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            await terminal.RestoreAsync(CancellationToken.None).ConfigureAwait(false);
        }
    }

    private static double NextTarget(double current) =>
        current >= 20 ? 10 : current >= 10 ? 5 : current >= 5 ? 1 : 20;
}
