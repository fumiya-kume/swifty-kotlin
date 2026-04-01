@file:OptIn(ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicLongArray

fun main() {
    val a = AtomicLongArray(3)
    val b = AtomicLongArray(3) { it.toLong() }

    a[0] = 7L
    println(a[0])                         // 7
    println(a.getAndSet(1, 8L))           // 0
    println(a.compareAndSet(1, 8L, 9L))   // true
    println(a.compareAndExchange(1, 9L, 10L)) // 9
    println(a.getAndAdd(0, 2L))           // 7
    println(a.addAndGet(0, 3L))           // 12
    println(a.getAndIncrement(0))         // 12
    println(a.incrementAndGet(0))         // 14
    println(a.getAndDecrement(0))         // 14
    println(a.decrementAndGet(0))         // 12
    println(a.length)                     // 3
    println(a.toString())                 // [12, 10, 0]
    println(b[2])                         // 2
}
