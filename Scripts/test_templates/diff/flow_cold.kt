import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flow<Int> { emit(1); emit(2) }
        .map { it * 2 }
        .filter { it > 0 }
        .take(2)
        .collect { println(it) }
}
