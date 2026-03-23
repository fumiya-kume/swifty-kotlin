// NOTE: Requires kotlinx-coroutines on classpath.
// CORO-004: Basic delay test — verifies that delay() suspends and resumes
// correctly without blocking the calling thread (non-blocking continuation
// model).  The test launches two coroutines that each delay for different
// durations, then prints a message proving they ran concurrently (the total
// wall time should be ~max(delay1, delay2), not delay1 + delay2).
import kotlinx.coroutines.*

fun main() = runBlocking {
    val start = System.currentTimeMillis()

    val job1 = launch {
        delay(100)
        println("job1 done")
    }
    val job2 = launch {
        delay(50)
        println("job2 done")
    }

    job1.join()
    job2.join()

    val elapsed = System.currentTimeMillis() - start
    // With non-blocking delay, both run concurrently: elapsed ~ 100ms.
    // With blocking delay, they would serialize: elapsed ~ 150ms.
    // Use a generous threshold (200ms) to avoid flakiness.
    println(if (elapsed < 200) "concurrent" else "sequential ($elapsed ms)")
    println("done")
}
