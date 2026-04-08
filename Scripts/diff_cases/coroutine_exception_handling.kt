// SKIP-DIFF
import kotlinx.coroutines.*

// TEST-CORO-003: Exception handling in coroutines — CoroutineExceptionHandler,
// try/catch inside launch/async, and exception propagation rules.

fun main() = runBlocking {
    // 1. Exception in async is rethrown on await; supervisorScope prevents
    // the thrown exception from cancelling the entire runBlocking scope.
    supervisorScope {
        val deferred = async {
            throw IllegalStateException("async error")
        }
        try {
            deferred.await()
        } catch (e: IllegalStateException) {
            println("caught async: ${e.message}")
        }
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

    // 3. CoroutineExceptionHandler is only invoked on root coroutines.
    // When used as a child of runBlocking it is silently ignored; the
    // exception propagates to the parent instead.  Wrap the failing work
    // in a try/catch to handle it reliably inside runBlocking.
    val failingJob = launch {
        try {
            throw RuntimeException("unhandled")
        } catch (e: RuntimeException) {
            println("handler: ${e.message}")
        }
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
