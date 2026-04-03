// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val sem = Semaphore(2)
    println(sem.availablePermits)  // 2
    sem.acquire()
    println(sem.availablePermits)  // 1
    println(sem.tryAcquire())      // true
    println(sem.availablePermits)  // 0
    println(sem.tryAcquire())      // false
    sem.release()
    sem.release()
    println(sem.availablePermits)  // 2
}
