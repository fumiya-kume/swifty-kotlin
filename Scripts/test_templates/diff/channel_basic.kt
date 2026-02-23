import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    val ch = Channel<Int>()
    launch { ch.send(42); ch.close() }
    println(ch.receive())
}
