// NOTE: Requires kotlinx-coroutines on classpath.
// diff_kotlinc.sh must be extended to include kotlinx-coroutines-core.jar
// before this template can be used with the diff harness.
import kotlinx.coroutines.*

fun main() = runBlocking {
    val deferred = async { 1 + 2 }
    println(deferred.await())
}
