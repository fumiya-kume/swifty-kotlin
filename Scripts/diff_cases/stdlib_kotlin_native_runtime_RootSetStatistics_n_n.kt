// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.runtime APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.NativeRuntimeApi
import kotlin.native.runtime.RootSetStatistics

@OptIn(NativeRuntimeApi::class)
fun makeRootSetStatistics(
    threadLocalReferences: Long,
    stackReferences: Long,
    globalReferences: Long,
    stableReferences: Long,
): Any = RootSetStatistics(
    threadLocalReferences,
    stackReferences,
    globalReferences,
    stableReferences,
)

fun main() {
    println(makeRootSetStatistics(1L, 2L, 3L, 4L) is RootSetStatistics)
}
