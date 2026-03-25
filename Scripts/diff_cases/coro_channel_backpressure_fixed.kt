// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    println("Testing Channel send/receive with backpressure")
    
    // Test default channel semantics
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
    println("Sender sent value")
    
    // Wait for completion
    receiverJob.join()
    println("Rendezvous test completed")
    
    // Launch a sender before the receiver to exercise blocking behavior again
    println("\nTesting sender-first handoff")
    val senderJob = launch {
        println("Sender attempting to send second value...")
        rendezvousChannel.send(7)
    }
    
    delay(200)
    val received2 = rendezvousChannel.receive()
    println("Main received second value: $received2")
    
    senderJob.join()
    println("Sender successfully sent: 7")
    
    println("Channel tests completed")
}
