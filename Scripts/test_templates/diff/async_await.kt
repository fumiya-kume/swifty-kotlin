import kotlinx.coroutines.*

fun main() = runBlocking {
    val deferred = async { 1 + 2 }
    println(deferred.await())
}
