import kotlinx.coroutines.*

suspend fun delayedValue(): Int {
    delay(1)
    return 42
}

suspend fun yieldingLoop(): Int {
    var sum = 0
    for (i in 1..3) {
        sum += i
        yield()
    }
    return sum
}

fun main() {
    val result = runBlocking {
        val scoped = coroutineScope {
            delay(1)
            10
        }

        val timed = withTimeout(5000L) {
            delay(1)
            20
        }

        val timedOrNull = withTimeoutOrNull(5000L) {
            delay(1)
            30
        }

        val yielded = yieldingLoop()

        println(scoped)
        println(timed)
        println(timedOrNull)
        println(yielded)
        scoped + timed + (timedOrNull ?: 0) + yielded
    }
    println(result)
}
