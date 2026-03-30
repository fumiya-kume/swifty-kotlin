// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val mutex = Mutex()
    println(mutex.isLocked)   // false
    mutex.lock()
    println(mutex.isLocked)   // true
    println(mutex.tryLock())  // false
    mutex.unlock()
    println(mutex.isLocked)   // false
    println(mutex.tryLock())  // true
    mutex.unlock()

    // withLock equivalent: acquire lock, run block, then release
    var counter = 0
    mutex.lock()
    counter++
    mutex.unlock()
    println(counter)          // 1
    println(mutex.isLocked)   // false

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
