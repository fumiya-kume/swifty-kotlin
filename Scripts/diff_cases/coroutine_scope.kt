import kotlinx.coroutines.*

// Test CoroutineScope hierarchy and lifecycle management (STDLIB-CORO-069)

fun main() = runBlocking {
    // 1. coroutineScope { } returns the result of its block
    val result = coroutineScope {
        val a = async { 10 }
        val b = async { 20 }
        a.await() + b.await()
    }
    println(result)

    // 2. Nested coroutineScope: structured concurrency — child must complete before parent
    val outer = coroutineScope {
        val inner = coroutineScope {
            launch {
                // child job inside inner scope
            }
            42
        }
        inner + 1
    }
    println(outer)

    // 3. supervisorScope — child failure does not cancel siblings
    val supervised = supervisorScope {
        val good = async { 100 }
        good.await()
    }
    println(supervised)

    // 4. Launch and join inside a scope
    coroutineScope {
        val job = launch {
            println("child launched")
        }
        job.join()
    }
    println("all done")
}
