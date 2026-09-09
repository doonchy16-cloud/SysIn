using System.Security.Cryptography;
using System.Text;

namespace SysIn.Core;

public static class DeviceIdFactory
{
    private const char Separator = '\u001F';

    public static DeviceId Create(DeviceKind kind, params string[] stableParts)
    {
        ArgumentNullException.ThrowIfNull(stableParts);

        var normalizedParts = stableParts
            .Select(static part => (part ?? string.Empty).Trim().ToUpperInvariant());

        var canonical = string.Join(
            Separator,
            new[] { kind.ToString().ToUpperInvariant() }.Concat(normalizedParts));

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
        var opaque = Convert.ToHexString(hash).ToLowerInvariant()[..24];

        return new DeviceId($"{kind.ToString().ToLowerInvariant()}:{opaque}");
    }
}
