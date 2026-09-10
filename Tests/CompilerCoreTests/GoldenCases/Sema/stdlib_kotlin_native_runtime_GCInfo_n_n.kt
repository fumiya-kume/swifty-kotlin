package golden.sema

import kotlin.native.runtime.GCInfo
import kotlin.native.runtime.MemoryUsage
import kotlin.native.runtime.RootSetStatistics
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun gcInfoConstructor(
    rootSet: RootSetStatistics,
    sweepStatistics: Map<String, SweepStatistics>,
    memoryUsageBefore: Map<String, MemoryUsage>,
    memoryUsageAfter: Map<String, MemoryUsage>,
): GCInfo = GCInfo(
    1L,
    2L,
    3L,
    4L,
    5L,
    6L,
    null,
    null,
    null,
    null,
    rootSet,
    7L,
    sweepStatistics,
    memoryUsageBefore,
    memoryUsageAfter,
)
