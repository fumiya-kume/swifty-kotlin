import kotlin.concurrent.AtomicInt
import kotlin.concurrent.AtomicLong
import kotlin.concurrent.AtomicReference
import kotlin.concurrent.AtomicBoolean

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

    // AtomicReference basics
    val ar = AtomicReference<String>("hello")
    println(ar.load())              // hello
    ar.store("world")
    println(ar.load())              // world
    println(ar.exchange("foo"))     // world
    println(ar.load())              // foo

    // AtomicBoolean basics
    val ab = AtomicBoolean(true)
    println(ab.load())              // true
    ab.store(false)
    println(ab.load())              // false
    println(ab.exchange(true))      // false
    println(ab.load())              // true

    // AtomicBoolean compareAndSet
    println(ab.compareAndSet(true, false))   // true
    println(ab.compareAndSet(true, false))   // false
    println(ab.load())                       // false

    // AtomicBoolean compareAndExchange
    println(ab.compareAndExchange(false, true))  // false
    println(ab.load())                           // true
}
