namespace SysIn.Views;

public sealed record RenderStats(
    double ActualFps,
    double TargetFps,
    TimeSpan LastFrameTime);
