@file:OptIn(ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.ExperimentalAtomicApi

typealias AtomicLongArray = kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val a = AtomicLongArray(3)
    val b = AtomicLongArray(3)

    a.storeAt(0, 7L)
    println(a.loadAt(0))                     // 7
    println(a.exchangeAt(1, 8L))              // 0
    println(a.compareAndSetAt(1, 8L, 9L))     // true
    println(a.compareAndExchangeAt(1, 9L, 10L)) // 9
    println(a.fetchAndAddAt(0, 2L))           // 7
    println(a.addAndFetchAt(0, 3L))           // 12
    println(a.fetchAndAddAt(0, 1L))           // 12
    println(a.addAndFetchAt(0, 1L))           // 14
    println(a.fetchAndAddAt(0, -1L))          // 14
    println(a.addAndFetchAt(0, -1L))          // 12
    println(a.size)                           // 3
    println(a.toString())                     // [12, 10, 0]
    b.storeAt(2, 2L)
    println(b.loadAt(2))                      // 2
}
