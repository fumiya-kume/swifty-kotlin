import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // flow { emit() } + map + collect
    flow { emit(1); emit(2) }
        .map { it * 2 }
        .collect { println(it) }

    // flow + filter + collect
    flow { emit(1); emit(2); emit(3); emit(4) }
        .filter { it % 2 == 0 }
        .collect { println(it) }

    // flow + map + filter + toList
    val list = flow { emit(1); emit(2); emit(3) }
        .map { it * 10 }
        .filter { it > 10 }
        .toList()
    println(list)

    // flow + first
    val f = flow { emit(42); emit(99) }
        .first()
    println(f)
}
