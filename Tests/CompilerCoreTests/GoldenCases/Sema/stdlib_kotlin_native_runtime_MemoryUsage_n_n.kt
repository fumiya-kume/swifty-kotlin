package golden.sema

import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun memoryUsageConstructor(): MemoryUsage = MemoryUsage(42L)
