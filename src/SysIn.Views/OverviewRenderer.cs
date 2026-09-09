using SysIn.Terminal;

namespace SysIn.Views;

public sealed class OverviewRenderer
{
    public void Render(
        OverviewViewModel model,
        FrameBuffer frame,
        SpectrumTheme theme,
        LayoutMode mode)
    {
        ArgumentNullException.ThrowIfNull(model);
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(theme);

        frame.Clear(new Cell(' ', theme.TextPrimary, theme.Background));

        if (mode == LayoutMode.MinimumSafe)
        {
            RenderMinimum(frame, theme);
            return;
        }

        if (mode == LayoutMode.Compact)
        {
            RenderCompact(model, frame, theme);
            return;
        }

        RenderDashboard(model, frame, theme, mode);
    }

    private static void RenderMinimum(FrameBuffer frame, SpectrumTheme theme)
    {
        Components.Fill(frame, 0, 0, frame.Width, frame.Height, theme.Background);
        frame.WriteText("SYSIN · more room needed", 2, Math.Min(2, frame.Height - 1), theme.Brand, theme.Background, clip: true);
        if (frame.Height > 4)
        {
            frame.WriteText("Resize to at least 80x24 or run: sysin snapshot", 2, 4, theme.TextPrimary, theme.Background, clip: true);
        }
    }

    private static void RenderCompact(OverviewViewModel model, FrameBuffer frame, SpectrumTheme theme)
    {
        Components.Fill(frame, 0, 0, frame.Width, 2, theme.Raised);
        frame.WriteText($"◆ SYSIN  OVERVIEW  ● LIVE  {model.Fps} FPS", 1, 0, theme.Brand, theme.Raised, clip: true);
        frame.WriteText(model.MachineName, 1, 1, theme.TextSecondary, theme.Raised, clip: true);

        var row = 3;
        Row(frame, ref row, "CPU", $"{model.CpuUtilization}  {model.CpuName}", theme.Cpu.Bright, theme);
        foreach (var gpu in model.Gpus)
        {
            Row(frame, ref row, "GPU", $"{gpu.Utilization}  {gpu.Name}", theme.Gpu.Bright, theme);
        }
        Row(frame, ref row, "MEMORY", model.Memory, theme.Memory.Bright, theme);
        Row(frame, ref row, "STORAGE", model.Storage, theme.Storage.Bright, theme);
        Row(frame, ref row, "NETWORK", model.Network, theme.Network.Bright, theme);
        Row(frame, ref row, "UPTIME", model.Uptime, theme.Info, theme);
        Row(frame, ref row, "PROVIDERS", model.ProviderHealth, theme.Processes.Bright, theme);

        Components.Fill(frame, 0, frame.Height - 2, frame.Width, 2, theme.Raised);
        frame.WriteText("[1] Overview  [/] Search  [P] Pause  [?] Help  [Q] Quit", 1, frame.Height - 1,
            theme.TextPrimary, theme.Raised, clip: true);
    }

    private static void Row(
        FrameBuffer frame,
        ref int row,
        string label,
        string value,
        Rgb24 accent,
        SpectrumTheme theme)
    {
        if (row >= frame.Height - 2)
        {
            return;
        }

        Components.Fill(frame, 1, row, frame.Width - 2, 2, theme.Surface);
        frame.Set(1, row, new Cell('▌', accent, theme.Surface));
        frame.WriteText(label, 3, row, accent, theme.Surface, clip: true);
        frame.WriteText(value, 15, row, theme.TextPrimary, theme.Surface, clip: true);
        row += 2;
    }

    private static void RenderDashboard(
        OverviewViewModel model,
        FrameBuffer frame,
        SpectrumTheme theme,
        LayoutMode mode)
    {
        var sidebarWidth = mode is LayoutMode.Xl or LayoutMode.Large ? 16 : 0;
        var contextWidth = mode is LayoutMode.Xl or LayoutMode.Large ? 30 : 0;
        var gap = 1;
        var mainX = sidebarWidth > 0 ? sidebarWidth + gap : 1;
        var mainWidth = frame.Width - mainX - contextWidth - (contextWidth > 0 ? gap + 1 : 1);
        var contextX = contextWidth > 0 ? frame.Width - contextWidth : frame.Width;

        Components.Fill(frame, 0, 0, frame.Width, 3, theme.Raised);
        frame.WriteText("◆ SYSIN 1.2 PREVIEW", 1, 0, theme.Brand, theme.Raised, clip: true);
        frame.WriteText($"OVERVIEW  ● LIVE   BALANCED   {model.Fps} FPS   ↑ {model.Uptime}",
            Math.Min(24, frame.Width - 1), 0, theme.TextPrimary, theme.Raised, clip: true);
        frame.WriteText(model.MachineName, 1, 1, theme.TextSecondary, theme.Raised, clip: true);

        if (sidebarWidth > 0)
        {
            Components.Fill(frame, 0, 3, sidebarWidth, frame.Height - 5, theme.Surface);
            var navigation = new[] { "▣ Overview", "● CPU", "● GPU", "● Memory", "● Storage", "● Network", "● Processes", "◇ Sensors", "✚ Doctor" };
            for (var i = 0; i < navigation.Length && i + 5 < frame.Height - 2; i++)
            {
                var color = i switch
                {
                    1 => theme.Cpu.Bright,
                    2 => theme.Gpu.Bright,
                    3 => theme.Memory.Bright,
                    4 => theme.Storage.Bright,
                    5 => theme.Network.Bright,
                    6 => theme.Processes.Bright,
                    _ => i == 0 ? theme.Brand : theme.TextSecondary
                };
                frame.WriteText(navigation[i], 1, 4 + (i * 2), color, theme.Surface, clip: true);
            }
        }

        var summaryY = 4;
        var summaryHeight = 5;
        var cardCount = Math.Max(4, 4 + model.Gpus.Count);
        var cardWidth = Math.Max(12, (mainWidth - (cardCount - 1)) / cardCount);
        var cardX = mainX;
        SummaryCard(frame, cardX, summaryY, cardWidth, "CPU", model.CpuUtilization, theme.Cpu.Bright, theme);
        cardX += cardWidth + 1;
        foreach (var gpu in model.Gpus)
        {
            if (cardX + cardWidth > mainX + mainWidth)
            {
                break;
            }
            SummaryCard(frame, cardX, summaryY, cardWidth, "GPU", gpu.Utilization, theme.Gpu.Bright, theme);
            cardX += cardWidth + 1;
        }
        if (cardX + cardWidth <= mainX + mainWidth)
        {
            SummaryCard(frame, cardX, summaryY, cardWidth, "RAM", model.Memory, theme.Memory.Bright, theme);
            cardX += cardWidth + 1;
        }
        if (cardX + cardWidth <= mainX + mainWidth)
        {
            SummaryCard(frame, cardX, summaryY, cardWidth, "NET", model.Network, theme.Network.Bright, theme);
        }

        var gridY = summaryY + summaryHeight + 1;
        var availableHeight = frame.Height - gridY - 4;
        var leftWidth = Math.Max(24, (mainWidth * 55) / 100);
        var rightX = mainX + leftWidth + 1;
        var rightWidth = Math.Max(20, mainWidth - leftWidth - 1);

        Components.Panel(frame, mainX, gridY, leftWidth, Math.Max(8, availableHeight / 2), "CPU · LIVE",
            theme.Cpu.Bright, theme.Surface, theme.TextPrimary);
        frame.WriteText($"{model.CpuUtilization}   {model.CpuName}", mainX + 3, gridY + 2,
            theme.Cpu.Bright, theme.Surface, clip: true);
        frame.WriteText("▁▂▄▆▇▅▃▅▆▄▂▃▅▇▆▃", mainX + 3, gridY + 4,
            theme.Cpu.Mid, theme.Surface, clip: true);

        var gpuPanelHeight = Math.Max(5, availableHeight / Math.Max(2, model.Gpus.Count + 1));
        var gpuY = gridY;
        foreach (var gpu in model.Gpus)
        {
            Components.Panel(frame, rightX, gpuY, rightWidth, gpuPanelHeight, "GPU",
                theme.Gpu.Bright, theme.Surface, theme.TextPrimary);
            frame.WriteText(gpu.Name, rightX + 3, gpuY + 1, theme.TextPrimary, theme.Surface, clip: true);
            frame.WriteText(gpu.Utilization, rightX + 3, gpuY + 2, theme.Gpu.Bright, theme.Surface, clip: true);
            gpuY += gpuPanelHeight + 1;
            if (gpuY + gpuPanelHeight > frame.Height - 3)
            {
                break;
            }
        }

        var lowerY = gridY + Math.Max(8, availableHeight / 2) + 1;
        var lowerHeight = Math.Max(5, frame.Height - lowerY - 3);
        if (lowerY + lowerHeight <= frame.Height - 2)
        {
            var third = Math.Max(15, (mainWidth - 2) / 3);
            Components.Panel(frame, mainX, lowerY, third, lowerHeight, "MEMORY", theme.Memory.Bright, theme.Surface, theme.TextPrimary);
            frame.WriteText(model.Memory, mainX + 3, lowerY + 2, theme.Memory.Bright, theme.Surface, clip: true);
            Components.Panel(frame, mainX + third + 1, lowerY, third, lowerHeight, "STORAGE", theme.Storage.Bright, theme.Surface, theme.TextPrimary);
            frame.WriteText(model.Storage, mainX + third + 4, lowerY + 2, theme.Storage.Bright, theme.Surface, clip: true);
            var netX = mainX + (third * 2) + 2;
            var netWidth = Math.Max(4, mainWidth - (third * 2) - 2);
            Components.Panel(frame, netX, lowerY, netWidth, lowerHeight, "NETWORK", theme.Network.Bright, theme.Surface, theme.TextPrimary);
            frame.WriteText(model.Network, netX + 3, lowerY + 2, theme.Network.Bright, theme.Surface, clip: true);
        }

        if (contextWidth > 0)
        {
            Components.Fill(frame, contextX, 3, contextWidth, frame.Height - 5, theme.Surface);
            frame.WriteText("CONTEXT", contextX + 2, 4, theme.Brand, theme.Surface, clip: true);
            frame.WriteText("✓ No active alerts", contextX + 2, 7, theme.TextPrimary, theme.Surface, clip: true);
            frame.WriteText("HARDWARE", contextX + 2, 11, theme.TextSecondary, theme.Surface, clip: true);
            frame.WriteText($"CPU  {model.CpuUtilization}", contextX + 2, 13, theme.Cpu.Bright, theme.Surface, clip: true);
            frame.WriteText($"GPU  {model.Gpus.Count}", contextX + 2, 15, theme.Gpu.Bright, theme.Surface, clip: true);
            frame.WriteText($"RAM  {model.Memory}", contextX + 2, 17, theme.Memory.Bright, theme.Surface, clip: true);
            frame.WriteText("SYSIN", contextX + 2, 22, theme.TextSecondary, theme.Surface, clip: true);
            frame.WriteText($"Providers {model.ProviderHealth}", contextX + 2, 24, theme.Processes.Bright, theme.Surface, clip: true);
            frame.WriteText($"Frame {model.FrameTime}", contextX + 2, 26, theme.Info, theme.Surface, clip: true);
        }

        Components.Fill(frame, 0, frame.Height - 2, frame.Width, 2, theme.Raised);
        frame.WriteText("[1] Overview [2] CPU [3] GPU [4] Memory [5] Storage [6] Network [/] Search [P] Pause [?] Help [Q] Quit",
            1, frame.Height - 1, theme.TextPrimary, theme.Raised, clip: true);
    }

    private static void SummaryCard(
        FrameBuffer frame,
        int x,
        int y,
        int width,
        string title,
        string value,
        Rgb24 accent,
        SpectrumTheme theme)
    {
        if (x + width > frame.Width || width < 4)
        {
            return;
        }

        Components.Fill(frame, x, y, width, 5, theme.Surface);
        frame.Set(x, y, new Cell('▌', accent, theme.Surface));
        frame.WriteText(title, x + 2, y + 1, accent, theme.Surface, clip: true);
        frame.WriteText(value, x + 2, y + 3, theme.TextPrimary, theme.Surface, clip: true);
    }
}
