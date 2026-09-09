using SysIn.Core;

namespace SysIn.Telemetry;

public sealed record FreshnessPolicy
{
    public TimeSpan FreshFor { get; }
    public TimeSpan AgingFor { get; }

    public FreshnessPolicy()
        : this(TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5))
    {
    }

    public FreshnessPolicy(TimeSpan freshFor, TimeSpan agingFor)
    {
        if (freshFor < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(freshFor));
        }

        if (agingFor < freshFor)
        {
            throw new ArgumentOutOfRangeException(nameof(agingFor), "Aging threshold must be greater than or equal to the fresh threshold.");
        }

        FreshFor = freshFor;
        AgingFor = agingFor;
    }

    public MetricFreshness Evaluate(MetricObservation observation, DateTimeOffset now)
    {
        if (observation.Availability != MetricAvailability.Available)
        {
            return MetricFreshness.NotApplicable;
        }

        var age = now - observation.ObservedAt;
        if (age < TimeSpan.Zero)
        {
            age = TimeSpan.Zero;
        }

        if (age <= FreshFor)
        {
            return MetricFreshness.Fresh;
        }

        return age <= AgingFor
            ? MetricFreshness.Aging
            : MetricFreshness.Stale;
    }
}
