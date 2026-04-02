@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val ints = AtomicIntArray(3)
    val longs = AtomicLongArray(2)

    println(ints.size)
    println(longs.size)

    ints.set(0, 10)
    ints.set(1, 20)
    longs.set(0, 100L)
    longs.set(1, 200L)

    println(ints.get(0))
    println(ints.get(1))
    println(longs.get(0))
    println(longs.get(1))

    println(ints.compareAndSet(0, 10, 11))
    println(ints.compareAndSet(1, 99, 22))
    println(ints.getAndAdd(0, 5))
    println(ints.get(0))

    println(longs.compareAndSet(1, 200L, 250L))
    println(longs.getAndAdd(1, 25L))
    println(longs.get(1))
}
