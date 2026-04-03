import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    flow<Int> {
        emit(1)
    }.catch { _: Throwable -> println(-1) }
        .collect { value: Int -> println(value) }

    val retried = flow<Int> {
        emit(10)
        emit(20)
    }.retry(1)
    println(retried.toList())

    val retriedWhen = flow<Int> {
        emit(7)
    }.retryWhen { _: Throwable, attempt: Long ->
        attempt < 1L
    }
    println(retriedWhen.toList())
}
