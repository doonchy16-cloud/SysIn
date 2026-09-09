namespace SysIn.Native.Tests;

public sealed class BootstrapTests
{
    [Fact]
    public void Native_tests_run_on_dotnet_10() =>
        Assert.Equal(10, Environment.Version.Major);
}
