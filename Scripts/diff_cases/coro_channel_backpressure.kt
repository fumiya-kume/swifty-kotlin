import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    println("Testing Channel send/receive with backpressure")

    // Test rendezvous channel (capacity = 0)
    val rendezvousChannel = Channel<Int>()

    // Launch receiver that will suspend
    val receiverJob = launch {
        println("Receiver waiting for value...")
        val received = rendezvousChannel.receive()
        println("Receiver received: $received")
    }

    // Give receiver time to start
    delay(100)

    // Send value - should suspend until receiver is ready
    println("Sender sending value...")
    rendezvousChannel.send(42)
    receiverJob.join()
    println("Sender sent value")

    println("Rendezvous test completed")

    println("Channel tests completed")
}
