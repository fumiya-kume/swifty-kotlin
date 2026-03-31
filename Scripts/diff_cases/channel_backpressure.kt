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

    // Test 4: Fan-out simulation (multiple consumers from same list)
    val fanOutData = listOf(10, 20, 30)
    val consumer1 = mutableListOf<Int>()
    val consumer2 = mutableListOf<Int>()
    for (v in fanOutData) {
        consumer1.add(v)
        consumer2.add(v * 2)
    }
    println("fanout consumer1: ${consumer1.joinToString(",")}")
    println("fanout consumer2: ${consumer2.joinToString(",")}")

    // Test 5: Fan-in simulation (multiple producers into one list)
    val fanInResult = mutableListOf<Int>()
    val producer1 = listOf(1, 2, 3)
    val producer2 = listOf(4, 5, 6)
    for (v in producer1) fanInResult.add(v)
    for (v in producer2) fanInResult.add(v)
    println("fanin result count: ${fanInResult.size}")

    // Test 6: Broadcast simulation (value replicated to multiple subscribers)
    val broadcastValue = 42
    val sub1 = broadcastValue
    val sub2 = broadcastValue
    println("broadcast sub1: $sub1")
    println("broadcast sub2: $sub2")

    // Test 7: Pipeline simulation (source -> transform -> sink)
    val source = listOf(1, 2, 3, 4, 5)
    val transformed = source.map { it * it }
    var pipelineSum = 0
    for (v in transformed) pipelineSum += v
    println("pipeline sum of squares: $pipelineSum")
}
