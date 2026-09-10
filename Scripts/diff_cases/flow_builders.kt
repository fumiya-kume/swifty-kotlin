import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flowOf(1, 2, 3)
        .collect { println(it) }

    emptyFlow<Int>()
        .collect { println(it) }

    listOf(4, 5, 6)
        .asFlow()
        .map { it * 10 }
        .collect { println(it) }

    channelFlow<Int> {
        send(7)
        send(8)
    }.collect { println(it) }

    callbackFlow<Int> {
        trySend(9)
        trySend(10)
        close()
    }.collect { println(it) }

    val offset = 70
    val reusableChannelFlow = channelFlow<Int> {
        send(offset + 1)
        send(offset + 2)
    }
    reusableChannelFlow.collect { println(it) }
    reusableChannelFlow.collect { println(it) }

    val reusableCallbackFlow = callbackFlow<Int> {
        val result = trySend(11)
        if (result.isSuccess) close()
    }
    reusableCallbackFlow.collect { println(it) }
    reusableCallbackFlow.collect { println(it) }
}
