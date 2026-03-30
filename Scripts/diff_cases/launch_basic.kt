import kotlinx.coroutines.*

fun main() = runBlocking {
    // Basic fire-and-forget launch
    val job = launch {
        println("launched")
    }
    job.join()
    println("joined")

    // Launch with dispatcher
    val job2 = launch(Dispatchers.Default) {
        println("on default dispatcher")
    }
    job2.join()

    // Launch with IO dispatcher
    val job3 = launch(Dispatchers.IO) {
        println("on IO dispatcher")
    }
    job3.join()

    // Job cancellation
    val job4 = launch {
        delay(1000)
        println("should not print")
    }
    job4.cancel()

    println("done")
}
