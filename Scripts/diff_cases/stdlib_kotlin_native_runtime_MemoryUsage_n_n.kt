// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val value: MemoryUsage = MemoryUsage(42L)
    println(value is MemoryUsage)
}
