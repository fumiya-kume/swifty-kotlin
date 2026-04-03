// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // Test 1: basic send / receive / close
    val ch = Channel<Int>()
    launch {
        ch.send(42)
        ch.close()
    }
    println(ch.receive())

    // Test 2: isClosedForReceive
    val ch2 = Channel<Int>()
    ch2.close()
    println(ch2.isClosedForReceive)

    // Test 3: buffered channel
    val buffered = Channel<Int>(capacity = 2)
    buffered.send(1)
    buffered.send(2)
    println(buffered.receive())
    println(buffered.receive())

    // Test 4: for-loop iteration
    val ch4 = Channel<Int>()
    launch {
        for (i in 1..3) {
            ch4.send(i)
        }
        ch4.close()
    }
    for (v in ch4) {
        println(v)
    }

    // Test 5: produce {}
    val produced = produce {
        send(99)
    }
    println(produced.receive())
}
