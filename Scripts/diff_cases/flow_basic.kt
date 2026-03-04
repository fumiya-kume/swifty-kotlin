import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flow { emit(1); emit(2) }
        .map { it * 2 }
        .collect { println(it) }
}
