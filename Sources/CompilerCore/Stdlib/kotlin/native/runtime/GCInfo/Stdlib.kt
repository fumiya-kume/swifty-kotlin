package kotlin.native.runtime

// KSP-1264: source-back the public GCInfo nominal declaration and constructor.
// Its property surface remains synthetic until KSP-1265.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class GCInfo(
    epoch: Long,
    startTimeNs: Long,
    endTimeNs: Long,
    firstPauseRequestTimeNs: Long,
    firstPauseStartTimeNs: Long,
    firstPauseEndTimeNs: Long,
    secondPauseRequestTimeNs: Long?,
    secondPauseStartTimeNs: Long?,
    secondPauseEndTimeNs: Long?,
    postGcCleanupTimeNs: Long?,
    rootSet: RootSetStatistics,
    markedCount: Long,
    sweepStatistics: Map<String, SweepStatistics>,
    memoryUsageBefore: Map<String, MemoryUsage>,
    memoryUsageAfter: Map<String, MemoryUsage>,
)
