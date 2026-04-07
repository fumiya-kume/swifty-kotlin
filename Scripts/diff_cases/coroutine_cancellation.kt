import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch {
        delay(10)
        println("job completed")
    }
    job.join()
    println("done")
}
