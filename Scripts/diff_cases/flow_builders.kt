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
        emit(7)
        emit(8)
    }.collect { println(it) }

    callbackFlow<Int> {
        emit(9)
        emit(10)
    }.collect { println(it) }
}
