using System.Management;
using SysIn.Core;

namespace SysIn.Platform.Windows;

internal static class WindowsGpuDiscovery
{
    public static IReadOnlyList<DeviceDescriptor> Discover()
    {
        var devices = new List<DeviceDescriptor>();

        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT PNPDeviceID, Name, DriverVersion, VideoProcessor FROM Win32_VideoController");
            using var results = searcher.Get();

            foreach (ManagementObject item in results)
            {
                using (item)
                {
                    var pnpId = item["PNPDeviceID"]?.ToString()?.Trim();
                    var name = item["Name"]?.ToString()?.Trim();
                    var driver = item["DriverVersion"]?.ToString()?.Trim();
                    var processor = item["VideoProcessor"]?.ToString()?.Trim();
                    var displayName = string.IsNullOrWhiteSpace(name) ? "Windows GPU" : name;

                    var stableParts = !string.IsNullOrWhiteSpace(pnpId)
                        ? new[] { pnpId }
                        : new[] { displayName, processor ?? string.Empty, driver ?? string.Empty };

                    devices.Add(new DeviceDescriptor(
                        DeviceIdFactory.Create(DeviceKind.Gpu, stableParts),
                        DeviceKind.Gpu,
                        displayName,
                        null,
                        processor,
                        new HashSet<DeviceRole>()));
                }
            }
        }
        catch (ManagementException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }

        return devices
            .GroupBy(device => device.Id)
            .Select(group => group.First())
            .ToArray();
    }
}
