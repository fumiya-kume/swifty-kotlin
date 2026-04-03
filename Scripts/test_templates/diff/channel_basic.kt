// NOTE: Requires kotlinx-coroutines on classpath.
// diff_kotlinc.sh must be extended to include kotlinx-coroutines-core.jar
// before this template can be used with the diff harness.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    val ch = Channel<Int>()
    launch {
        ch.send(42)
        ch.close()
    }
    println(ch.receive())

    val buffered = Channel<Int>(capacity = 2)
    buffered.send(1)
    buffered.send(2)
    println(buffered.receive())
    println(buffered.receive())

    val produced = produce {
        send(99)
    }
    println(produced.receive())
}
