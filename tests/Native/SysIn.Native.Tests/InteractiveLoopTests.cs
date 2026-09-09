using SysIn.App;
using SysIn.Terminal;
using SysIn.Views;

namespace SysIn.Native.Tests;

public sealed class InteractiveLoopTests
{
    private sealed class CountingDelay : IDelayScheduler
    {
        public int Calls { get; private set; }

        public ValueTask DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
        {
            Assert.True(delay > TimeSpan.Zero);
            cancellationToken.ThrowIfCancellationRequested();
            Calls++;
            return ValueTask.CompletedTask;
        }
    }

    [Fact]
    public async Task Loop_enters_restores_and_paces_frames()
    {
        var terminal = new VirtualTerminalHost(120, 35, TerminalCapabilities.Premium);
        var delay = new CountingDelay();
        var loop = new InteractiveLoop(
            terminal,
            TestFixtures.DualGpuSnapshot,
            OverviewViewModel.FromSnapshot,
            new OverviewRenderer(),
            SpectrumTheme.Default,
            TimeProvider.System,
            delay,
            static () => { },
            static () => false,
            20,
            3);

        await loop.RunAsync(CancellationToken.None);

        Assert.Equal(1, terminal.EnterCount);
        Assert.Equal(1, terminal.RestoreCount);
        Assert.True(delay.Calls >= 2);
    }
}
