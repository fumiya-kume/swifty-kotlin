import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch {
        println("launched")
    }
    job.join()
    println("joined")

    val result = withContext(Dispatchers.Default) {
        "from default dispatcher"
    }
    println(result)

    println("done")
}
