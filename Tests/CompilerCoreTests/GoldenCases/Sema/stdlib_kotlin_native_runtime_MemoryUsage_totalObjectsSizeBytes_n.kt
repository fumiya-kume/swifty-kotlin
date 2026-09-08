package golden.sema

import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun memoryUsageTotalObjectsSizeBytes(): Long {
    val memoryUsage = MemoryUsage(-9223372036854775807L - 1L)
    return memoryUsage.totalObjectsSizeBytes
}
