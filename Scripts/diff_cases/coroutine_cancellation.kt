// SKIP-DIFF: structured cancellation catch parity still differs from kotlinc runtime semantics.
// NOTE: Requires kotlinx-coroutines on classpath.
// diff_kotlinc.sh must be extended to include kotlinx-coroutines-core.jar
// before this template can be used with the diff harness.
import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch {
        try {
            repeat(1000) {
                delay(10)
            }
        } catch (e: CancellationException) {
            println("cancelled")
        }
    }
    delay(50)
    job.cancel()
    job.join()
    println("done")
}
