@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicBoolean

fun main() {
    println(AtomicBoolean(false).load())
    println(AtomicBoolean(true).load())
}
