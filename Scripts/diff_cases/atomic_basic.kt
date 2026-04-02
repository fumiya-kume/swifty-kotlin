@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

fun main() {
    // AtomicReference basics
    val ar = AtomicReference("hello")
    println(ar.load())              // hello
    ar.store("world")
    println(ar.load())              // world
    println(ar.exchange("foo"))     // world
    println(ar.load())              // foo
    println(ar.compareAndSet("foo", "bar"))   // true
    println(ar.compareAndExchange("bar", "baz")) // bar
    println(ar.getAndUpdate { it + "!" })      // baz
    println(ar.updateAndGet { it + "?" })      // baz!
    println(ar.load())                          // baz!?
}
