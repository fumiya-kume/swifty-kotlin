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

    // withLock: acquire lock, run block, then release automatically
    val withLockResult = mutex.withLock { 1 }
    println(withLockResult)       // 1
    println(mutex.isLocked)       // false
    println(mutex.tryLock())      // true
    mutex.unlock()
}
