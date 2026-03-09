// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*

fun main() = runBlocking {
    val result = withContext(Dispatchers.Default) {
        "hello from context"
    }
    println(result)
}
