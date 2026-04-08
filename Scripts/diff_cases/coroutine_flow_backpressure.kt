// SKIP-DIFF: advanced coroutine APIs (CoroutineScope, ReceiveChannel, produce) not yet implemented
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// TEST-CORO-003: Flow backpressure — buffer, conflate, and collectLatest
// demonstrate how flows handle slow collectors.

fun fastProducer(): Flow<Int> = flow {
    for (i in 1..5) {
        emit(i)
        delay(1)
    }
}

fun main() = runBlocking {
    // 1. Basic flow collection
    val collected = mutableListOf<Int>()
    fastProducer().collect { collected.add(it) }
    println("collected: ${collected.size}")

    // 2. buffer() — producer and consumer run concurrently
    val buffered = mutableListOf<Int>()
    fastProducer()
        .buffer(3)
        .collect {
            delay(2)
            buffered.add(it)
        }
    println("buffered: ${buffered.size}")

    // 3. conflate() — skip intermediate values when collector is slow
    val conflated = mutableListOf<Int>()
    fastProducer()
        .conflate()
        .collect {
            delay(5)
            conflated.add(it)
        }
    println("conflated count: ${conflated.isNotEmpty()}")

    // 4. collectLatest — cancel and restart on each new emission
    var latestSeen = -1
    fastProducer()
        .collectLatest { value ->
            delay(3)
            latestSeen = value
        }
    println("latestSeen: $latestSeen")

    println("done")
}
