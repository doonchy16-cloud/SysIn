using SysIn.Core;

namespace SysIn.Telemetry;

public static class MetricCatalog
{
    public static readonly MetricId CpuUtilization = new("cpu.utilization");
    public static readonly MetricId MemoryUsed = new("memory.physical.used");
    public static readonly MetricId MemoryAvailable = new("memory.available");
    public static readonly MetricId MemoryUtilization = new("memory.utilization");
    public static readonly MetricId GpuUtilization = new("gpu.utilization");
    public static readonly MetricId StorageUsed = new("storage.used");
    public static readonly MetricId StorageCapacity = new("storage.capacity");
    public static readonly MetricId NetworkReceiveRate = new("network.receive.rate");
    public static readonly MetricId NetworkTransmitRate = new("network.transmit.rate");
    public static readonly MetricId SystemUptime = new("system.uptime");
}
