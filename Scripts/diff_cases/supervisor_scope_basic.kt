// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*

fun main() = runBlocking {
    val result = supervisorScope {
        val deferred = async { 1 + 2 }
        deferred.await()
    }
    println(result)
}
