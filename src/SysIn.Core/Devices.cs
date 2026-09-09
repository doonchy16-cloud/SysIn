namespace SysIn.Core;

public enum DeviceKind
{
    System,
    Cpu,
    Gpu,
    Memory,
    PhysicalStorage,
    Volume,
    NetworkAdapter,
    Process,
    Sensor,
    Battery
}

public enum DeviceRole
{
    Integrated,
    Discrete,
    Display,
    HighPerformance
}

public sealed record DeviceDescriptor(
    DeviceId Id,
    DeviceKind Kind,
    string Name,
    string? Vendor,
    string? Model,
    IReadOnlySet<DeviceRole> Roles);
