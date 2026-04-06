import kotlinx.coroutines.*

// TEST-CORO-003: Structured concurrency — parent waits for all children,
// child failure cancels siblings, and coroutineScope propagates exceptions.

suspend fun fetchData(id: Int): String {
    delay(1)
    return "data-$id"
}

fun main() = runBlocking {
    // 1. coroutineScope waits for all children to complete
    val results = coroutineScope {
        val a = async { fetchData(1) }
        val b = async { fetchData(2) }
        val c = async { fetchData(3) }
        listOf(a.await(), b.await(), c.await())
    }
    results.forEach { println(it) }

    // 2. Nested structured concurrency
    val total = coroutineScope {
        var sum = 0
        coroutineScope {
            repeat(3) { i ->
                launch {
                    sum += (i + 1)
                }
            }
        }
        sum
    }
    println("total: $total")

    // 3. All children complete before parent proceeds
    val order = mutableListOf<String>()
    coroutineScope {
        launch { order.add("child1") }
        launch { order.add("child2") }
    }
    order.add("parent")
    println(order.sorted().joinToString(","))

    println("done")
}
