// NOTE: Requires kotlinx-coroutines on classpath.
// diff_kotlinc.sh must be extended to include kotlinx-coroutines-core.jar
// before this template can be used with the diff harness.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    val started = Channel<Int>()
    val job = launch {
        try {
            started.send(1)
            repeat(1000) {
                delay(10)
            }
        } catch (e: CancellationException) {
            println("cancelled")
        }
    }
    started.receive()
    job.cancel()
    job.join()
    println("done")
}
