@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicReference

fun main() {
    val ref = AtomicReference("a")
    println(ref.load())
    println(ref.compareAndSet("x", "b"))
    println(ref.compareAndSet("a", "b"))
    println(ref.exchange("c"))
    println(ref.getAndUpdate { it + "!" })
    println(ref.updateAndGet { it + "?" })
    println(ref.load())

    val count = AtomicInt(1)
    println(count.load())
    println(count.addAndFetch(4))
    println(count.fetchAndAdd(3))
    println(count.compareAndExchange(8, 10))
    println(count.compareAndExchange(9, 10))
    println(count.load())
}
