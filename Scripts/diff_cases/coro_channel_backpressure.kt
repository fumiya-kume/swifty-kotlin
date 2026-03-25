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
    println("Sender sent value")
    
    // Wait for completion
    receiverJob.join()
    println("Rendezvous test completed")
    
    // Test buffered channel with backpressure
    println("\nTesting buffered channel with backpressure")
    val bufferedChannel = Channel<Int>(capacity = 2)
    
    // Fill buffer to capacity
    bufferedChannel.send(1)
    bufferedChannel.send(2)
    println("Buffer filled with values: 1, 2")
    
    // Launch receiver that will process one value
    val bufferReceiverJob = launch {
        delay(100) // Give sender time to suspend
        val received1 = bufferedChannel.receive()
        println("Buffer receiver received: $received1")
    }
    
    // Try to send third value - should suspend due to backpressure
    println("Sender attempting to send to full buffer...")
    val senderJob = launch {
        bufferedChannel.send(3)
        println("Sender successfully sent: 3")
    }
    
    // Give some time then receive to make space
    delay(200)
    val received2 = bufferedChannel.receive()
    println("Main received from buffer: $received2")
    
    // Wait for sender to complete
    senderJob.join()
    bufferReceiverJob.join()
    
    println("Channel tests completed")
}
