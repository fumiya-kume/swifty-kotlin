package golden.sema

import kotlin.native.runtime.NativeRuntimeApi
import kotlin.native.runtime.RootSetStatistics

@OptIn(NativeRuntimeApi::class)
fun makeRootSetStatistics(
    threadLocalReferences: Long,
    stackReferences: Long,
    globalReferences: Long,
    stableReferences: Long,
): RootSetStatistics = RootSetStatistics(
    threadLocalReferences,
    stackReferences,
    globalReferences,
    stableReferences,
)
