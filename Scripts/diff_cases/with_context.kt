// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*

fun main() = runBlocking {
    // Basic withContext with dispatcher
    val result = withContext(Dispatchers.Default) {
        "hello from context"
    }
    println(result)

    // withContext with IO dispatcher
    val ioResult = withContext(Dispatchers.IO) {
        "io result"
    }
    println(ioResult)

    // withContext with context composition (+ operator)
    val composed = Dispatchers.Default + CoroutineName("myCoroutine")
    val composedResult = withContext(composed) {
        "composed context result"
    }
    println(composedResult)

    // Nested withContext
    val nested = withContext(Dispatchers.Default) {
        val inner = withContext(Dispatchers.IO) {
            "inner"
        }
        "outer + $inner"
    }
    println(nested)

    println("done")
}
