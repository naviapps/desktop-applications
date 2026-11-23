namespace NaviApps.DesktopApplications.Tests;

internal sealed class ObservationClock : TimeProvider
{
    private readonly Lock gate = new();
    private readonly List<ScheduledTimer> timers = [];
    private long timestamp;

    public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    public override long GetTimestamp() { lock (gate) return timestamp; }
    internal bool IsIdle { get { lock (gate) return timers.Count == 0; } }

    internal void AdvanceTo(double milliseconds)
    {
        ScheduledTimer[] due;
        lock (gate)
        {
            timestamp = TimeSpan.FromMilliseconds(milliseconds).Ticks;
            due = timers.Where(timer => timer.Deadline <= timestamp).OrderBy(timer => timer.Deadline).ToArray();
            foreach (var timer in due)
                timer.Deadline = timer.Period > TimeSpan.Zero ? timer.Deadline + timer.Period.Ticks : long.MaxValue;
        }
        foreach (var timer in due) timer.Fire();
    }

    public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
    {
        lock (gate)
        {
            var timer = new ScheduledTimer(this, callback, state);
            timer.Change(dueTime, period);
            timers.Add(timer);
            return timer;
        }
    }

    private sealed class ScheduledTimer(ObservationClock clock, TimerCallback callback, object? state) : ITimer
    {
        internal long Deadline { get; set; }
        internal TimeSpan Period { get; private set; }
        internal void Fire() => callback(state);

        public bool Change(TimeSpan dueTime, TimeSpan period)
        {
            lock (clock.gate)
            {
                Deadline = dueTime == Timeout.InfiniteTimeSpan ? long.MaxValue : clock.timestamp + dueTime.Ticks;
                Period = period;
                return true;
            }
        }

        public void Dispose() { lock (clock.gate) clock.timers.Remove(this); }
        public ValueTask DisposeAsync()
        {
            Dispose();
            return ValueTask.CompletedTask;
        }
    }
}
