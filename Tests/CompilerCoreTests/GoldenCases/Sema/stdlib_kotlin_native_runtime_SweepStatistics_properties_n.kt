package golden.sema

import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun sweepStatisticsProperties(): Long {
    val statistics = SweepStatistics(-9223372036854775807L - 1L, 9223372036854775807L)
    return statistics.sweptCount + statistics.keptCount
}
