// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val minimum = SweepStatistics(-9223372036854775807L - 1L, 9223372036854775807L)
    println(minimum.sweptCount)
    println(minimum.keptCount)
}
