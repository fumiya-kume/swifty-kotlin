import kotlinx.coroutines.flow.*

fun main() {
    val state = MutableStateFlow(10)
    println(state.value)
}
