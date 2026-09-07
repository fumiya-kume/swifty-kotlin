@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.AtomicIntArray

fun atomicIntArrayFromSize(size: Int): AtomicIntArray = AtomicIntArray(size)
fun atomicIntArrayFromStorage(values: IntArray): AtomicIntArray = AtomicIntArray(values)
