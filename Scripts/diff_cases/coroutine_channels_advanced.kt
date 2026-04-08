// SKIP-DIFF
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

// TEST-CORO-003: Advanced channel communication — producer/consumer pattern,
// fan-out, fan-in, and closing channels.

fun CoroutineScope.produce(from: Int, to: Int): ReceiveChannel<Int> = produce {
    for (i in from..to) {
        send(i)
        delay(1)
    }
}

fun main() = runBlocking {
    // 1. Basic producer/consumer
    val channel = produce(1, 5)
    val received = mutableListOf<Int>()
    for (item in channel) {
        received.add(item)
    }
    println("received: ${received.size}")

    // 2. Buffered channel
    val buffered = Channel<Int>(4)
    launch {
        repeat(4) { buffered.send(it) }
        buffered.close()
    }
    val buf = mutableListOf<Int>()
    for (v in buffered) buf.add(v)
    println("buffered: ${buf.size}")

    // 3. Fan-out: multiple consumers from one channel
    val source = Channel<Int>(10)
    repeat(6) { source.send(it) }
    source.close()
    val results1 = mutableListOf<Int>()
    val results2 = mutableListOf<Int>()
    val c1 = launch { for (v in source) results1.add(v) }
    val c2 = launch { for (v in source) results2.add(v) }
    c1.join(); c2.join()
    println("fan-out total: ${results1.size + results2.size}")

    // 4. Channel isClosedForReceive after close
    val ch = Channel<String>()
    ch.close()
    println("closed: ${ch.isClosedForReceive}")

    println("done")
}
