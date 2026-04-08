// SKIP-DIFF
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

// TEST-CORO-003: Mutex and Semaphore — protecting shared state in coroutines,
// withLock helper, and Semaphore for limiting concurrent access.

fun main() = runBlocking {
    // 1. Mutex protects shared counter
    val mutex = Mutex()
    var counter = 0
    val jobs = (1..100).map {
        launch(Dispatchers.Default) {
            mutex.withLock {
                counter++
            }
        }
    }
    jobs.forEach { it.join() }
    println("counter: $counter")

    // 2. Mutex.withLock returns value of block
    val result = mutex.withLock { "locked result" }
    println("result: $result")

    // 3. Mutex is not held after withLock
    println("isLocked: ${mutex.isLocked}")

    // 4. Semaphore limits concurrency
    val semaphore = Semaphore(3)
    var maxConcurrent = 0
    var current = 0
    val semJobs = (1..10).map {
        launch(Dispatchers.Default) {
            semaphore.withPermit {
                current++
                if (current > maxConcurrent) maxConcurrent = current
                delay(1)
                current--
            }
        }
    }
    semJobs.forEach { it.join() }
    println("max concurrent <= 3: ${maxConcurrent <= 3}")

    // 5. Semaphore with 1 permit acts like a mutex
    val binarySema = Semaphore(1)
    var shared = 0
    val semaJobs = (1..50).map {
        launch(Dispatchers.Default) {
            binarySema.withPermit { shared++ }
        }
    }
    semaJobs.forEach { it.join() }
    println("binary sema shared: $shared")

    println("done")
}
