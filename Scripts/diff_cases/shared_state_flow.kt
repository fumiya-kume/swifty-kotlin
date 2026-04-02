import kotlinx.coroutines.flow.*

fun main() {
    val shared = MutableSharedFlow<Int>(2)
    shared.emit(1)
    shared.emit(2)
    shared.emit(3)
    for (value in shared.replayCache) {
        println(value)
    }
    shared.collect { println(it) }

    val state = MutableStateFlow(10)
    println(state.value)
    state.emit(20)
    println(state.value)
    state.collect { println(it) }

    val sharedFromCold = flowOf(4, 5, 6).shareIn(2)
    for (value in sharedFromCold.replayCache) {
        println(value)
    }

    val stateFromCold = flowOf(7, 8).stateIn(0)
    println(stateFromCold.value)
}
