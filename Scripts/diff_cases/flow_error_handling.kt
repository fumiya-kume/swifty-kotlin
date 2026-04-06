import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // catch: handle upstream exception, suppress it
    flow<Int> {
        emit(1)
    }.catch { _: Throwable -> println(-1) }
        .collect { value: Int -> println(value) }

    // retry: retry on failure (no failure here, so retries are not exercised)
    val retried = flow<Int> {
        emit(10)
        emit(20)
    }.retry(1)
    println(retried.toList())

    // retryWhen: conditional retry with attempt count
    val retriedWhen = flow<Int> {
        emit(7)
    }.retryWhen { _: Throwable, attempt: Long ->
        attempt < 1L
    }
    println(retriedWhen.toList())

    // onErrorReturn: emit fallback value on error
    val withFallback = flow<Int> {
        emit(42)
    }.onErrorReturn(99)
    println(withFallback.toList())

    // onErrorResume: switch to fallback flow on error
    val fallback = flowOf(100, 200)
    val withResume = flow<Int> {
        emit(5)
    }.onErrorResume(fallback)
    println(withResume.toList())

    // onCompletion: run side-effect after flow completes normally
    flow<Int> {
        emit(3)
        emit(6)
    }.onCompletion { cause: Throwable? ->
        if (cause == null) println("done") else println("error")
    }.collect { value: Int -> println(value) }
}
