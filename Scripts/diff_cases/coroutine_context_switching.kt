// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
import kotlinx.coroutines.*

// TEST-CORO-003: withContext switching — change dispatcher within a coroutine,
// combining context elements, and verifying execution resumes correctly.

suspend fun compute(): Int = withContext(Dispatchers.Default) {
    // CPU-bound work simulation
    var sum = 0
    for (i in 1..100) sum += i
    sum
}

suspend fun ioTask(): String = withContext(Dispatchers.IO) {
    delay(1)
    "io-result"
}

fun main() = runBlocking {
    // 1. Switch to Default for computation
    val result = compute()
    println("compute: $result")

    // 2. Switch to IO for I/O simulation
    val io = ioTask()
    println("io: $io")

    // 3. Switch back to original dispatcher
    val combined = withContext(Dispatchers.Default) {
        val a = async { compute() }
        val b = async { compute() }
        a.await() + b.await()
    }
    println("combined: $combined")

    // 4. Nested withContext calls
    val nested = withContext(Dispatchers.Default) {
        withContext(Dispatchers.IO) {
            "nested-io"
        }
    }
    println("nested: $nested")

    // 5. withContext preserves result type
    val typed: List<Int> = withContext(Dispatchers.Default) {
        listOf(1, 2, 3)
    }
    println("typed size: ${typed.size}")

    println("done")
}
