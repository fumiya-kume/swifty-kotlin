// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
import kotlinx.coroutines.*

// TEST-CORO-003: Coroutine edge cases — empty scope, immediate cancellation,
// yield behaviour, and nested runBlocking equivalents.

fun main() = runBlocking {
    // 1. Empty coroutineScope completes immediately
    coroutineScope { }
    println("empty scope ok")

    // 2. Job that is cancelled before it starts running
    val job = launch(start = CoroutineStart.LAZY) {
        println("should not print")
    }
    job.cancel()
    job.join()
    println("lazy-cancelled: ${job.isCancelled}")

    // 3. yield() gives other coroutines a chance to run
    val order = mutableListOf<Int>()
    launch {
        order.add(1)
        yield()
        order.add(3)
    }
    launch {
        order.add(2)
        yield()
        order.add(4)
    }
    yield()
    yield()
    println("order ok: ${order.size == 4}")

    // 4. Nested async — result is available after await
    val nested = async {
        async { 21 }.await() * 2
    }
    println("nested: ${nested.await()}")

    // 5. isActive check inside coroutine
    var sawActive = false
    val checker = launch {
        sawActive = isActive
    }
    checker.join()
    println("wasActive: $sawActive")

    println("done")
}
