// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
import kotlinx.coroutines.*

// TEST-CORO-003: Advanced cancellation — cooperative cancellation via
// isActive / ensureActive, cancellation with cause, and finally blocks.

suspend fun cancellableWork(): String {
    var count = 0
    while (currentCoroutineContext().isActive && count < 5) {
        delay(1)
        count++
    }
    return "done-$count"
}

fun main() = runBlocking {
    // 1. Job cancelled mid-loop via isActive
    val job1 = launch {
        val r = cancellableWork()
        println("work: $r")
    }
    delay(3)
    job1.cancel()
    job1.join()

    // 2. ensureActive throws CancellationException when cancelled
    val job2 = launch {
        repeat(10) {
            ensureActive()
            delay(1)
        }
        println("ensureActive completed")
    }
    job2.cancel()
    job2.join()
    println("job2 cancelled: ${job2.isCancelled}")

    // 3. finally block runs on cancellation
    val job3 = launch {
        try {
            delay(Long.MAX_VALUE)
        } finally {
            println("finally ran")
        }
    }
    job3.cancel()
    job3.join()

    // 4. withContext(NonCancellable) protects cleanup
    val job4 = launch {
        try {
            delay(Long.MAX_VALUE)
        } finally {
            withContext(NonCancellable) {
                delay(1)
                println("cleanup done")
            }
        }
    }
    job4.cancel()
    job4.join()

    println("done")
}
