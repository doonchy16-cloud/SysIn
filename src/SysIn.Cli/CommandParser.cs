namespace SysIn.Cli;

public enum NativeCommand
{
    Overview,
    Snapshot,
    Version,
    Doctor,
    Help,
    Invalid
}

public sealed record ParsedCommand(NativeCommand Command, bool Json, string? Error);

public static class CommandParser
{
    private static readonly IReadOnlyDictionary<string, NativeCommand> Commands =
        new Dictionary<string, NativeCommand>(StringComparer.OrdinalIgnoreCase)
        {
            ["overview"] = NativeCommand.Overview,
            ["snapshot"] = NativeCommand.Snapshot,
            ["version"] = NativeCommand.Version,
            ["doctor"] = NativeCommand.Doctor,
            ["help"] = NativeCommand.Help
        };

    public static ParsedCommand Parse(IReadOnlyList<string> args)
    {
        ArgumentNullException.ThrowIfNull(args);

        if (args.Count == 0)
        {
            return new ParsedCommand(NativeCommand.Overview, false, null);
        }

        var token = args[0];
        if (!Commands.TryGetValue(token, out var command))
        {
            return new ParsedCommand(NativeCommand.Invalid, false, BuildUnknownCommandError(token));
        }

        if (args.Count == 1)
        {
            return new ParsedCommand(command, false, null);
        }

        if (command == NativeCommand.Snapshot
            && args.Count == 2
            && string.Equals(args[1], "--json", StringComparison.OrdinalIgnoreCase))
        {
            return new ParsedCommand(command, true, null);
        }

        return new ParsedCommand(
            NativeCommand.Invalid,
            false,
            command == NativeCommand.Snapshot
                ? "snapshot accepts only the optional flag: --json"
                : $"{token} does not accept additional arguments in this Preview.");
    }

    private static string BuildUnknownCommandError(string token)
    {
        var suggestion = Commands.Keys
            .Select(candidate => (Candidate: candidate, Distance: EditDistance(token, candidate)))
            .Where(item => item.Distance <= 2)
            .OrderBy(item => item.Distance)
            .ThenBy(item => item.Candidate, StringComparer.Ordinal)
            .Select(item => item.Candidate)
            .FirstOrDefault();

        return suggestion is null
            ? $"Unknown command '{token}'. Use 'sysin help'."
            : $"Unknown command '{token}'. Did you mean '{suggestion}'?";
    }

    private static int EditDistance(string left, string right)
    {
        left ??= string.Empty;
        right ??= string.Empty;

        var previous = new int[right.Length + 1];
        var current = new int[right.Length + 1];
        for (var j = 0; j <= right.Length; j++)
        {
            previous[j] = j;
        }

        for (var i = 1; i <= left.Length; i++)
        {
            current[0] = i;
            for (var j = 1; j <= right.Length; j++)
            {
                var substitution = char.ToUpperInvariant(left[i - 1]) == char.ToUpperInvariant(right[j - 1]) ? 0 : 1;
                current[j] = Math.Min(
                    Math.Min(current[j - 1] + 1, previous[j] + 1),
                    previous[j - 1] + substitution);
            }

            (previous, current) = (current, previous);
        }

        return previous[right.Length];
    }
}
