// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.NativeRuntimeApi
import kotlin.native.runtime.SweepStatistics

@OptIn(NativeRuntimeApi::class)
fun main() {
    SweepStatistics(1L, 2L)
    println("sweep_statistics_ok=true")
}
