package kotlin.native.runtime

// KSP-1267: Keep the native GC memory-pool measurement source-backed.
// Kotlin/Native reports the total allocated object size in bytes, excluding
// system allocator overhead while including alignment and object headers.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class MemoryUsage(
    public val totalObjectsSizeBytes: Long,
)
