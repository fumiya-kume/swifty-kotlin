import kotlinx.coroutines.*

// TEST-CORO-003: Exception handling in coroutines — CoroutineExceptionHandler,
// try/catch inside launch/async, and exception propagation rules.

fun main() = runBlocking {
    // 1. Exception in async is rethrown on await
    val deferred = async {
        throw IllegalStateException("async error")
    }
    try {
        deferred.await()
    } catch (e: IllegalStateException) {
        println("caught async: ${e.message}")
    }

    // 2. try/catch inside launch catches the exception locally
    val job = launch {
        try {
            error("launch error")
        } catch (e: IllegalStateException) {
            println("caught launch: ${e.message}")
        }
    }
    job.join()

    // 3. CoroutineExceptionHandler receives uncaught exceptions from launch
    val handler = CoroutineExceptionHandler { _, throwable ->
        println("handler: ${throwable.message}")
    }
    val failingJob = launch(handler) {
        throw RuntimeException("unhandled")
    }
    failingJob.join()

    // 4. CancellationException is not treated as a failure
    val cancelJob = launch {
        try {
            delay(Long.MAX_VALUE)
        } catch (e: CancellationException) {
            println("cancelled cleanly")
            throw e
        }
    }
    cancelJob.cancel()
    cancelJob.join()

    println("done")
}
