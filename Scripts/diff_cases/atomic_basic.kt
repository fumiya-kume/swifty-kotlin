// SKIP-DIFF: Synthetic atomic APIs are not present in upstream kotlinc.
import kotlin.concurrent.AtomicInt
import kotlin.concurrent.AtomicLong
import kotlin.concurrent.AtomicBoolean
import kotlin.concurrent.AtomicReference
import kotlin.concurrent.AtomicNativePtr
import kotlinx.cinterop.NativePtr

fun main() {
    // AtomicInt basics
    val ai = AtomicInt(10)
    println(ai.load())             // 10
    ai.store(20)
    println(ai.load())             // 20
    println(ai.exchange(30))       // 20
    println(ai.load())             // 30

    // compareAndSet
    println(ai.compareAndSet(30, 40))  // true
    println(ai.compareAndSet(30, 50))  // false
    println(ai.load())                 // 40

    // compareAndExchange
    println(ai.compareAndExchange(40, 60))  // 40
    println(ai.compareAndExchange(99, 70))  // 60
    println(ai.load())                      // 60

    // arithmetic
    println(ai.fetchAndAdd(5))         // 60
    println(ai.load())                 // 65
    println(ai.addAndFetch(5))         // 70
    println(ai.fetchAndIncrement())    // 70
    println(ai.incrementAndFetch())    // 72
    println(ai.decrementAndFetch())    // 71

    // getAndUpdate / updateAndGet for AtomicInt
    println(ai.getAndUpdate { it * 2 })   // 71
    println(ai.load())                     // 142
    println(ai.updateAndGet { it + 1 })   // 143
    println(ai.load())                     // 143

    // AtomicLong basics
    val al = AtomicLong(100L)
    println(al.load())              // 100
    al.store(200L)
    println(al.load())              // 200
    println(al.exchange(300L))      // 200
    println(al.compareAndSet(300L, 400L))  // true
    println(al.load())                     // 400
    println(al.fetchAndAdd(10L))           // 400
    println(al.incrementAndFetch())        // 411
    println(al.decrementAndFetch())        // 410

    // getAndUpdate / updateAndGet for AtomicLong
    println(al.getAndUpdate { it + 10L })  // 410
    println(al.load())                      // 420
    println(al.updateAndGet { it - 5L })   // 415
    println(al.load())                      // 415

    // AtomicBoolean basics
    val ab = AtomicBoolean(false)
    println(ab.load())                          // false
    ab.store(true)
    println(ab.load())                          // true
    println(ab.exchange(false))                 // true
    println(ab.load())                          // false
    println(ab.compareAndSet(false, true))      // true
    println(ab.compareAndSet(false, true))      // false
    println(ab.load())                          // true
    println(ab.compareAndExchange(true, false)) // true
    println(ab.load())                          // false

    // getAndUpdate / updateAndGet for AtomicBoolean
    println(ab.getAndUpdate { !it })  // false
    println(ab.load())                 // true
    println(ab.updateAndGet { !it })   // false
    println(ab.load())                 // false

    // AtomicReference basics
    val ar = AtomicReference("hello")
    println(ar.load())              // hello
    ar.store("world")
    println(ar.load())              // world
    println(ar.exchange("foo"))     // world
    println(ar.load())              // foo

    // AtomicNativePtr basics
    val np: NativePtr = 0L
    val anp = AtomicNativePtr(np)
    println(anp.load())             // 0
    anp.store(42L)
    println(anp.load())             // 42
    println(anp.exchange(7L))       // 42
    println(anp.compareAndSet(7L, 9L))  // true
    println(anp.compareAndExchange(9L, 11L))  // 9
    println(anp.getAndUpdate { it + 1 })      // 11
    println(anp.updateAndGet { it + 1 })      // 13
}
