import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking

fun main() {
    runBlocking {
        flow {
            emit(1)
            emit(2)
        }.map { it * 2 }
            .collect { println(it) }
    }
}
