// SKIP-DIFF: uses kotlin.coroutines.cancellation.cancel import which is not available
// in kotlinc without a special classpath; the diff harness does not yet include
// kotlinx-coroutines-core.jar so the reference compiler always rejects this file.
// NOTE: Requires kotlinx-coroutines on classpath.
// diff_kotlinc.sh must be extended to include kotlinx-coroutines-core.jar
// before this template can be used with the diff harness.
import kotlinx.coroutines.*
import kotlin.coroutines.cancellation.cancel

fun main() = runBlocking {
    val job = launch {
        try {
            cancel("top-level cancel", Throwable("because"))
            delay(10)
        } catch (e: CancellationException) {
            println(e.message)
            println(e.cause?.message)
        }
    }
    job.join()
    println("done")
}
