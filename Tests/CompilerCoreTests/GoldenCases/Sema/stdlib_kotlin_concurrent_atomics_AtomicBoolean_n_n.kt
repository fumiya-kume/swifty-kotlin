@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicBoolean

fun atomicBooleanConstructorSemantics(): Boolean {
    val falseValue = AtomicBoolean(false)
    val trueValue = AtomicBoolean(true)
    return falseValue.load() || trueValue.load()
}
