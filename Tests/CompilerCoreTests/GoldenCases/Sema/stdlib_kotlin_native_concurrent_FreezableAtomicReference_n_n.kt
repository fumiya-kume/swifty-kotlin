@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.FreezableAtomicReference

fun construct(value: Int): FreezableAtomicReference<Int> =
    FreezableAtomicReference(value)
