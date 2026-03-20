// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // Test 1: Buffered channel backpressure
    val buffered = Channel<Int>(2)
    launch {
        for (i in 1..4) {
            buffered.send(i)
            println("sent $i")
        }
        buffered.close()
    }
    delay(100) // let sender fill buffer and block
    for (v in buffered) {
        println("received $v")
    }

    // Test 2: close() returns boolean
    val ch2 = Channel<Int>(1)
    println("first close: ${ch2.close()}")
    println("second close: ${ch2.close()}")

    // Test 3: Rendezvous channel send/receive pairing
    val rendezvous = Channel<Int>()
    launch {
        rendezvous.send(99)
        println("rendezvous sent")
    }
    println("rendezvous received: ${rendezvous.receive()}")
    rendezvous.close()
}
