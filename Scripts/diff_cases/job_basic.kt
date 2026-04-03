// SKIP-DIFF: Job.awaitCompletion() is a kswiftc-only API validated by runtime tests.
import kotlinx.coroutines.*

fun main() = runBlocking {
    // Test isActive, isCompleted, isCancelled before join
    val job = launch {
        delay(10)
    }
    println(job.isActive)     // true
    println(job.isCompleted)  // false
    println(job.isCancelled)  // false
    job.join()

    // Test cancel sets isCancelled
    val job2 = launch {
        delay(10000)
    }
    println(job2.isActive)    // true
    println(job2.isCancelled) // false
    job2.cancel()
    println(job2.isCancelled) // true
    job2.awaitCompletion()
    println("done")
}
