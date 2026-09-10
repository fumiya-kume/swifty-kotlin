@file:OptIn(kotlin.ExperimentalStdlibApi::class)

/*
 * KSP-1083: Kotlin 2.3.10 kotlin.concurrent top-level declarations.
 *
 * The nominal declarations are source-backed shells. Constructors and member
 * implementations remain owned by the follow-up TODOs and are supplied by
 * the residual runtime-backed registration until those migrations land.
 */

package kotlin.concurrent

import kotlinx.cinterop.ExperimentalForeignApi
import kotlin.internal.KsSymbolName

@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicArray<T> private constructor()

@SinceKotlin("1.9")
public class AtomicInt private constructor()

@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicIntArray private constructor()

@SinceKotlin("1.9")
public class AtomicLong private constructor()

@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicLongArray private constructor()

@SinceKotlin("1.9")
@ExperimentalForeignApi
public class AtomicNativePtr private constructor()

@SinceKotlin("1.9")
public class AtomicReference<T> private constructor()

@SinceKotlin("1.9")
@ExperimentalStdlibApi
public inline fun AtomicIntArray(size: Int, init: (Int) -> Int): AtomicIntArray {
    val result = AtomicIntArray(size)
    for (index in 0 until size) {
        result[index] = init(index)
    }
    return result
}

@SinceKotlin("1.9")
@ExperimentalStdlibApi
public inline fun AtomicLongArray(size: Int, init: (Int) -> Long): AtomicLongArray {
    val result = AtomicLongArray(size)
    for (index in 0 until size) {
        result[index] = init(index)
    }
    return result
}

@KsSymbolName("kk_atomic_ref_array_of")
@PublishedApi
internal external fun <T> atomicArrayFromArray(array: Array<T>): AtomicArray<T>

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@Suppress("UNCHECKED_CAST")
public inline fun <reified T> AtomicArray(size: Int, init: (Int) -> T): AtomicArray<T> {
    val inner = arrayOfNulls<T>(size)
    for (index in 0 until size) {
        inner[index] = init(index)
    }
    return atomicArrayFromArray(inner as Array<T>)
}
