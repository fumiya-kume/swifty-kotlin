package golden.sema

import kotlin.coroutines.cancellation.cancel
import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch {
        delay(10)
    }
    job.cancel()
    job.join()
}
