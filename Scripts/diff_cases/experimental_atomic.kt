@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val ints = AtomicIntArray(3)
    ints.storeAt(0, 1)
    ints.storeAt(1, 10)
    println(ints.size)
    println(ints.loadAt(0))
    println(ints.loadAt(1))
    println(ints.compareAndSetAt(1, 10, 11))
    println(ints.exchangeAt(0, 2))
    println(ints.addAndFetchAt(1, 4))
    println(ints.addAndFetchAt(2, 1))

    val longs = AtomicLongArray(2)
    longs.storeAt(0, 100L)
    longs.storeAt(1, 7L)
    println(longs.compareAndExchangeAt(0, 100L, 125L))
    println(longs.fetchAndAddAt(1, 5L))
    println(longs.addAndFetchAt(1, -1L))
    println(longs.loadAt(0))
}
