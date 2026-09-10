// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.GCInfo
import kotlin.native.runtime.MemoryUsage
import kotlin.native.runtime.RootSetStatistics
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val value: GCInfo = GCInfo(
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
        TODO(),
        7L,
        TODO(),
        TODO(),
        TODO(),
    )
    println(value is GCInfo)
}
