package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual
import kotlin.experimental.ExperimentalTypeInference
import kotlin.sequences.Sequence

// KSP-428
// List collection operations and numeric helpers migrated from the Swift
// runtime collection bridges.

private fun <T> listIterableContains(elements: Iterable<T>, value: T): Boolean {
    for (element in elements) {
        if (__valuesEqual(element, value)) return true
    }
    return false
}

public operator fun <T> Iterable<T>.plus(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}

public operator fun <T> Iterable<T>.plus(elements: Iterable<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

public operator fun <T> Iterable<T>.plus(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

public operator fun <T> Iterable<T>.plus(elements: Sequence<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

public operator fun <T> Iterable<T>.minus(element: T): List<T> {
    val result = mutableListOf<T>()
    var removed = false
    for (item in this) {
        if (!removed && __valuesEqual(item, element)) {
            removed = true
        } else {
            result.add(item)
        }
    }
    return result
}

public operator fun <T> Iterable<T>.minus(elements: Iterable<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) {
        if (!listIterableContains(elements, item)) result.add(item)
    }
    return result
}

public operator fun <T> Iterable<T>.minus(elements: Array<out T>): List<T> {
    if (elements.isEmpty()) return this.toList()
    val other = elements.toList()
    val result = mutableListOf<T>()
    for (item in this) {
        if (!listIterableContains(other, item)) result.add(item)
    }
    return result
}

public operator fun <T> Iterable<T>.minus(elements: Sequence<T>): List<T> {
    val other = elements.toList()
    if (other.isEmpty()) return this.toList()
    val result = mutableListOf<T>()
    for (item in this) {
        if (!listIterableContains(other, item)) result.add(item)
    }
    return result
}

public infix fun <T> Iterable<T>.intersect(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (listIterableContains(other, element)) result.add(element)
    }
    return result
}

public infix fun <T> Iterable<T>.union(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    for (element in other) result.add(element)
    return result
}

public infix fun <T> Iterable<T>.subtract(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (!listIterableContains(other, element)) result.add(element)
    }
    return result
}

public fun <T> Iterable<T>.distinct(): List<T> {
    val result = mutableListOf<T>()
    val seen = mutableSetOf<T>()
    for (element in this) {
        if (seen.add(element)) result.add(element)
    }
    return result
}

public fun <T, K> Iterable<T>.distinctBy(selector: (T) -> K): List<T> {
    val result = mutableListOf<T>()
    val seen = mutableSetOf<K>()
    for (element in this) {
        if (seen.add(selector(element))) result.add(element)
    }
    return result
}

// JVM-only @JvmName aliases are intentionally omitted: KSwiftK targets Native,
// where overload identity is represented by the full Kotlin signature/mangler.

public fun Iterable<Byte>.sum(): Int {
    var sum = 0
    for (element in this) sum += element
    return sum
}

public fun Iterable<Double>.sum(): Double {
    var sum = 0.0
    for (element in this) sum += element
    return sum
}

public fun Iterable<Float>.sum(): Float {
    var sum = 0.0f
    for (element in this) sum += element
    return sum
}

public fun Iterable<Int>.sum(): Int {
    var sum = 0
    for (element in this) sum += element
    return sum
}

public fun Iterable<Long>.sum(): Long {
    var sum = 0L
    for (element in this) sum += element
    return sum
}

public fun Iterable<Short>.sum(): Int {
    var sum = 0
    for (element in this) sum += element
    return sum
}

public fun Iterable<UByte>.sum(): UInt {
    var sum = 0u
    for (element in this) sum += element
    return sum
}

public fun Iterable<UInt>.sum(): UInt {
    var sum = 0u
    for (element in this) sum += element
    return sum
}

public fun Iterable<ULong>.sum(): ULong {
    var sum = 0uL
    for (element in this) sum += element
    return sum
}

public fun Iterable<UShort>.sum(): UInt {
    var sum = 0u
    for (element in this) sum += element
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Iterable<T>.sumOf(selector: (T) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun <T> Iterable<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Iterable<T>.sumOf(selector: (T) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun <T> Iterable<T>.sumOf(selector: (T) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Iterable<T>.sumOf(selector: (T) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

public fun List<Int>.sum(): Int {
    var sum = 0
    for (element in this) sum += element
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun <T> Iterable<T>.sumBy(selector: (T) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun <T> Iterable<T>.sumByDouble(selector: (T) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

public fun List<Int>.average(): Double {
    if (size == 0) return Double.NaN
    var total = 0
    for (element in this) total += element
    return total.toDouble() / size.toDouble()
}

public fun List<Double>.average(): Double {
    if (size == 0) return Double.NaN
    var total = 0.0
    for (element in this) total += element
    return total / size.toDouble()
}

public fun <T> Iterable<T>.reversed(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    var left = 0
    var right = result.size - 1
    while (left < right) {
        val temporary = result[left]
        result[left] = result[right]
        result[right] = temporary
        left++
        right--
    }
    return result
}

@KsSymbolName("__kk_list_as_reversed")
private external fun <T> __kk_list_as_reversed(list: List<T>): List<T>

public fun <T> List<T>.asReversed(): List<T> {
    return __kk_list_as_reversed(this)
}

public fun <T> Iterable<T>.plusElement(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}

public fun <T> Iterable<T>.minusElement(element: T): List<T> {
    val result = mutableListOf<T>()
    var removed = false
    for (item in this) {
        if (!removed && __valuesEqual(item, element)) {
            removed = true
        } else {
            result.add(item)
        }
    }
    return result
}
