fun main() {
    // Test 1: Simulated buffered channel using a list
    val buffer = mutableListOf<Int>()
    for (i in 1..4) {
        buffer.add(i)
        println("sent $i")
    }
    for (v in buffer) {
        println("received $v")
    }

    // Test 2: Channel-like close semantics with boolean flag
    var closed = false
    println("first close: ${!closed}")
    closed = true
    println("second close: ${!closed}")

    // Test 3: Direct value passing
    val value = 99
    println("rendezvous sent")
    println("rendezvous received: $value")
}
