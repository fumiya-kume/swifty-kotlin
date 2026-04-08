// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
import kotlinx.coroutines.*

// TEST-CORO-003: CoroutineScope lifecycle — creating, using, and cancelling
// a custom scope; verifying children are cancelled when scope is cancelled.

class MyService {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    fun start(): Job = scope.launch {
        delay(Long.MAX_VALUE)
    }

    fun stop() {
        scope.cancel()
    }

    val isActive: Boolean get() = scope.isActive
}

fun main() = runBlocking {
    val service = MyService()
    println("service active: ${service.isActive}")

    val job = service.start()
    delay(1)
    println("job active: ${job.isActive}")

    service.stop()
    delay(1)
    println("service active after stop: ${service.isActive}")
    println("job cancelled: ${job.isCancelled}")

    // CoroutineScope created inline
    val localScope = CoroutineScope(Job())
    val child = localScope.launch {
        delay(100)
        println("should not print")
    }
    localScope.cancel()
    child.join()
    println("child cancelled: ${child.isCancelled}")

    // coroutineScope {} auto-cancels children if one throws
    try {
        coroutineScope {
            launch { delay(Long.MAX_VALUE) }
            throw RuntimeException("scope error")
        }
    } catch (e: RuntimeException) {
        println("caught: ${e.message}")
    }

    println("done")
}
