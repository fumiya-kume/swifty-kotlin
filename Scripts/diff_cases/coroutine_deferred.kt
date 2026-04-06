import kotlinx.coroutines.*

// TEST-CORO-003: Deferred values — async/await, lazy deferred, multiple
// awaiters, and combining results from parallel async operations.

suspend fun heavyComputation(n: Int): Int {
    delay(1)
    return n * n
}

fun main() = runBlocking {
    // 1. Basic async/await
    val d1 = async { heavyComputation(4) }
    println("deferred: ${d1.await()}")

    // 2. Multiple async in parallel
    val jobs = (1..5).map { n -> async { heavyComputation(n) } }
    val results = jobs.map { it.await() }
    println("results: ${results.sum()}")

    // 3. Lazy async — does not start until await() or start() is called
    val lazy = async(start = CoroutineStart.LAZY) {
        println("lazy started")
        42
    }
    println("before await")
    val lazyResult = lazy.await()
    println("lazy result: $lazyResult")

    // 4. await on already-completed deferred returns immediately
    val eager = async { 99 }
    eager.await() // ensure completed
    println("re-await: ${eager.await()}")

    // 5. awaitAll shorthand
    val all = awaitAll(
        async { "a" },
        async { "b" },
        async { "c" }
    )
    println("awaitAll: ${all.joinToString(",")}")

    println("done")
}
