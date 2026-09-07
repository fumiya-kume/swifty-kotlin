package golden.sema

import kotlin.native.runtime.NativeRuntimeApi
import kotlin.native.runtime.SweepStatistics

@OptIn(NativeRuntimeApi::class)
fun makeSweepStatistics(): SweepStatistics = SweepStatistics(1L, 2L)
