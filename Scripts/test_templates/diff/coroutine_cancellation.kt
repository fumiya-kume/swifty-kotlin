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
