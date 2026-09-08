// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val minimum = MemoryUsage(-9223372036854775807L - 1L)
    val maximum = MemoryUsage(9223372036854775807L)
    println(minimum.totalObjectsSizeBytes)
    println(maximum.totalObjectsSizeBytes)
}
