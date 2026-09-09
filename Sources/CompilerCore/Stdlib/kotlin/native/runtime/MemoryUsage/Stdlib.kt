package kotlin.native.runtime

// KSP-1266: Keep the nominal declaration and constructor source-backed.
// The totalObjectsSizeBytes property remains synthetic until KSP-1267.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class MemoryUsage(totalObjectsSizeBytes: Long)
