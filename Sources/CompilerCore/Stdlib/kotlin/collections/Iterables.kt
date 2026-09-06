package kotlin.collections

import kotlin.comparisons.compareValues
import kotlin.comparisons.reverseOrder
import kotlin.internal.__valuesEqual
import kotlin.random.Random

// Float/Double maxOf uses these existing shared numeric helpers so NaN and
// signed-zero behavior stays identical to kotlin.comparisons.maxOf.
private external fun kk_max_float(a: Float, b: Float): Float
private external fun kk_max_double(a: Double, b: Double): Double
private external fun kk_unbox_float(value: Float): Float
private external fun kk_unbox_double(value: Double): Double

// KSP-435
// Generic Iterable<T> surface migrated from the Swift runtime `kk_iterable_*`
// bridges. Every implementation only relies on `iterator()` virtual dispatch,
// so it works for List, Set and any user-defined Iterable alike.

// KSP-963: Kotlin's Iterable.asIterable() is an identity conversion.
public inline fun <T> Iterable<T>.asIterable(): Iterable<T> = this

public fun <T> Iterable<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.drop(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n == 0) return toList()

    val result = mutableListOf<T>()
    var count = 0
    for (element in this) {
        if (count >= n) result.add(element) else count += 1
    }
    return result
}

public inline fun <T> Iterable<T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    var yielding = false
    val result = mutableListOf<T>()
    for (element in this) {
        if (yielding) {
            result.add(element)
        } else if (!predicate(element)) {
            result.add(element)
            yielding = true
        }
    }
    return result
}

public fun <T> Iterable<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

// KSP-997: Split each pair from a generic Iterable in encounter order.
public fun <T, R> Iterable<Pair<T, R>>.unzip(): Pair<List<T>, List<R>> {
    val first = mutableListOf<T>()
    val second = mutableListOf<R>()
    val iterator = iterator()
    while (iterator.hasNext()) {
        val pair = iterator.next()
        first.add(pair.first)
        second.add(pair.second)
    }
    return Pair(first, second)
}

public fun <T> Iterable<T>.shuffled(): List<T> {
    val result = this.toMutableList()
    var i = result.size - 1
    while (i > 0) {
        val j = Random.nextInt(i + 1)
        val temporary = result[i]
        result[i] = result[j]
        result[j] = temporary
        i -= 1
    }
    return result
}

public fun <T> Iterable<T>.shuffled(random: Random): List<T> {
    val result = this.toMutableList()
    var i = result.size - 1
    while (i > 0) {
        val j = random.nextInt(i + 1)
        val temporary = result[i]
        result[i] = result[j]
        result[j] = temporary
        i -= 1
    }
    return result
}

public fun <T> Iterable<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.toHashSet(): HashSet<T> {
    val result = HashSet<T>()
    for (element in this) result.add(element)
    return result
}

@IgnorableReturnValue
public fun <T, C : MutableCollection<in T>> Iterable<T>.toCollection(destination: C): C {
    for (element in this) destination.add(element)
    return destination
}

public fun <T> Iterable<Iterable<T>>.flatten(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        for (nestedElement in element) result.add(nestedElement)
    }
    return result
}

// KSP-974: Iterable flat-map transformations are source-backed. Keep the
// Iterable and Sequence inner-result overloads distinct so lambda-return-type
// overload resolution selects the same public API as the Kotlin stdlib.
public inline fun <T, R> Iterable<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequence")
public inline fun <T, R> Iterable<T>.flatMap(transform: (T) -> Sequence<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterable")
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.flatMapIndexed(transform: (index: Int, T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedSequence")
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.flatMapIndexed(transform: (index: Int, T) -> Sequence<R>): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterableTo")
@IgnorableReturnValue
@kotlin.internal.InlineOnly
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapIndexedTo(
    destination: C,
    transform: (index: Int, T) -> Iterable<R>
): C {
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedSequenceTo")
@IgnorableReturnValue
@kotlin.internal.InlineOnly
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapIndexedTo(
    destination: C,
    transform: (index: Int, T) -> Sequence<R>
): C {
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapTo(
    destination: C,
    transform: (T) -> Iterable<R>
): C {
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequenceTo")
@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapTo(
    destination: C,
    transform: (T) -> Sequence<R>
): C {
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> Iterable<Pair<K, V>>.toMap(): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (pair in this) result[pair.first] = pair.second
    return result as Map<K, V>
}

@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public fun <K, V, M : MutableMap<in K, in V>> Iterable<Pair<K, V>>.toMap(destination: M): M {
    // The bundled MutableMap stub exposes invariant operator parameters; the
    // official contravariant API permits every K/V write to this destination.
    val typedDestination = destination as MutableMap<K, V>
    for (pair in this) typedDestination[pair.first] = pair.second
    return destination
}

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result as Set<T>
}

public fun <T> Collection<T>.isNotEmpty(): Boolean = !isEmpty()

public fun <T> Iterable<T>.first(): T {
    for (element in this) return element
    throw NoSuchElementException("Collection is empty.")
}

public inline fun <T> Iterable<T>.first(predicate: (T) -> Boolean): T {
    for (element in this) {
        if (predicate(element)) return element
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> Iterable<T>.firstOrNull(): T? {
    for (element in this) return element
    return null
}

public inline fun <T> Iterable<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    for (element in this) {
        if (predicate(element)) return element
    }
    return null
}

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.last(): T {
    var found = false
    var last: T? = null
    for (element in this) {
        last = element
        found = true
    }
    if (!found) throw NoSuchElementException("Collection is empty.")
    return last as T
}

// KSP-965: numeric Iterable averages are source-backed and preserve iterator order.
private fun checkAverageCountOverflow(count: Int): Int {
    if (count < 0) throw ArithmeticException("Count overflow has happened.")
    return count
}

@kotlin.jvm.JvmName("averageOfByte")
public fun Iterable<Byte>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@kotlin.jvm.JvmName("averageOfShort")
public fun Iterable<Short>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@kotlin.jvm.JvmName("averageOfInt")
public fun Iterable<Int>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@kotlin.jvm.JvmName("averageOfLong")
public fun Iterable<Long>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@kotlin.jvm.JvmName("averageOfFloat")
public fun Iterable<Float>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@kotlin.jvm.JvmName("averageOfDouble")
public fun Iterable<Double>.average(): Double {
    var sum: Double = 0.0
    var count: Int = 0
    for (element in this) {
        sum += element
        count += 1
        checkAverageCountOverflow(count)
    }
    return if (count == 0) Double.NaN else sum / count
}

@Suppress("UNCHECKED_CAST")
public inline fun <T> Iterable<T>.last(predicate: (T) -> Boolean): T {
    var last: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            last = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return last as T
}

public fun <T> Iterable<T>.lastIndexOf(element: T): Int {
    var lastIndex = -1
    var index = 0
    for (item in this) {
        if (__valuesEqual(element, item)) lastIndex = index
        index++
    }
    return lastIndex
}

public fun <T> Iterable<T>.lastOrNull(): T? {
    var last: T? = null
    for (element in this) last = element
    return last
}

public inline fun <T> Iterable<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var last: T? = null
    for (element in this) {
        if (predicate(element)) last = element
    }
    return last
}

// KSP-970: generic Iterable element access keeps the List fast path while
// using one iterator traversal for non-List receivers.
public fun <T> Iterable<T>.elementAt(index: Int): T {
    if (this is List) {
        val list = this
        if (index < 0 || index >= list.size) {
            throw IndexOutOfBoundsException("Index $index out of bounds for length ${list.size}")
        }
        return list[index]
    }
    return elementAtOrElse(index) { throw IndexOutOfBoundsException("Collection doesn't contain element at index $index.") }
}

public fun <T> Iterable<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (this is List) {
        val list = this
        if (index >= 0 && index < list.size) return list[index]
        return defaultValue(index)
    }
    if (index < 0) return defaultValue(index)
    val iterator = iterator()
    var count = 0
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (index == count++) return element
    }
    return defaultValue(index)
}

public fun <T> Iterable<T>.elementAtOrNull(index: Int): T? {
    if (this is List) {
        val list = this
        if (index >= 0 && index < list.size) return list[index]
        return null
    }
    if (index < 0) return null
    val iterator = iterator()
    var count = 0
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (index == count++) return element
    }
    return null
}

// KSP-701: generic Iterable HOFs formerly registered by the compiler-side
// synthetic member registry now use bundled Kotlin source bodies.
public fun <T> Iterable<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

// KSP-982: source-backed Iterable map-family implementations. Keep these
// overloads independent from concrete List/Array/Set/Sequence receivers so
// virtual iterator dispatch also covers custom and one-shot Iterables.
public inline fun <T, R> Iterable<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) result.add(transform(element))
    return result
}

public inline fun <T, R> Iterable<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        result.add(transform(index, element))
        index += 1
    }
    return result
}

public inline fun <T, R : Any> Iterable<T>.mapIndexedNotNull(transform: (Int, T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        val transformed = transform(index, element)
        if (transformed != null) result.add(transformed)
        index += 1
    }
    return result
}

@IgnorableReturnValue
public inline fun <T, R : Any, C : MutableCollection<in R>> Iterable<T>.mapIndexedNotNullTo(
    destination: C,
    transform: (Int, T) -> R?
): C {
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        val transformed = transform(index, element)
        if (transformed != null) destination.add(transformed)
        index += 1
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.mapIndexedTo(
    destination: C,
    transform: (Int, T) -> R
): C {
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        destination.add(transform(index, element))
        index += 1
    }
    return destination
}

public inline fun <T, R : Any> Iterable<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val transformed = transform(element)
        if (transformed != null) result.add(transformed)
    }
    return result
}

@IgnorableReturnValue
public inline fun <T, R : Any, C : MutableCollection<in R>> Iterable<T>.mapNotNullTo(
    destination: C,
    transform: (T) -> R?
): C {
    for (element in this) {
        val transformed = transform(element)
        if (transformed != null) destination.add(transformed)
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.mapTo(
    destination: C,
    transform: (T) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <T> Iterable<T>.find(predicate: (T) -> Boolean): T? {
    for (element in this) {
        if (predicate(element)) return element
    }
    return null
}

public inline fun <T> Iterable<T>.findLast(predicate: (T) -> Boolean): T? {
    var last: T? = null
    for (element in this) {
        if (predicate(element)) last = element
    }
    return last
}

// KSP-971: remaining Iterable filter-family APIs use bundled Kotlin source
// bodies so custom and one-shot Iterable receivers follow the same iteration
// and destination semantics as the Kotlin standard library.
public inline fun <T> Iterable<T>.filterIndexed(predicate: (Int, T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public inline fun <T, C : MutableCollection<in T>> Iterable<T>.filterIndexedTo(
    destination: C,
    predicate: (Int, T) -> Boolean
): C {
    var index = 0
    for (element in this) {
        if (predicate(index, element)) destination.add(element)
        index++
    }
    return destination
}

public inline fun <reified R> Iterable<*>.filterIsInstance(): List<R> {
    val destination = mutableListOf<R>()
    for (element in this) {
        if (element is R) destination.add(element)
    }
    return destination
}

public inline fun <reified R, C : MutableCollection<in R>> Iterable<*>.filterIsInstanceTo(
    destination: C
): C {
    for (element in this) {
        if (element is R) destination.add(element)
    }
    return destination
}

public inline fun <T> Iterable<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) result.add(element)
    }
    return result
}

public fun <T : Any> Iterable<T?>.filterNotNull(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (element != null) result.add(element)
    }
    return result
}

public fun <C : MutableCollection<in T>, T : Any> Iterable<T?>.filterNotNullTo(
    destination: C
): C {
    for (element in this) {
        if (element != null) destination.add(element)
    }
    return destination
}

public inline fun <T, C : MutableCollection<in T>> Iterable<T>.filterNotTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    for (element in this) {
        if (!predicate(element)) destination.add(element)
    }
    return destination
}

public inline fun <T, C : MutableCollection<in T>> Iterable<T>.filterTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    for (element in this) {
        if (predicate(element)) destination.add(element)
    }
    return destination
}

public inline fun <T> Iterable<T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> {
    val first = ArrayList<T>()
    val second = ArrayList<T>()
    for (element in this) {
        if (predicate(element)) {
            first.add(element)
        } else {
            second.add(element)
        }
    }
    return Pair(first, second)
}

// KSP-995: source-backed generic Iterable take family.
public fun <T> Iterable<T>.take(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n == 0) return emptyList()

    val result = mutableListOf<T>()
    var count = 0
    for (element in this) {
        result.add(element)
        count += 1
        if (count == n) break
    }
    return result
}

public inline fun <T> Iterable<T>.takeWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) break
        result.add(element)
    }
    return result
}

public inline fun <S, T : S> Iterable<T>.reduce(operation: (acc: S, T) -> S): S {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator: S = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceIndexed(operation: (index: Int, acc: S, T) -> S): S {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator: S = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index += 1
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceOrNull(operation: (acc: S, T) -> S): S? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var accumulator: S = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceIndexedOrNull(operation: (index: Int, acc: S, T) -> S): S? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var accumulator: S = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index += 1
    }
    return accumulator
}

// KSP-992: generic Iterable single-family APIs use one iterator and stop as soon
// as their result is determined. List receivers continue to use ListSearchHOF.kt.
public fun <T> Iterable<T>.single(): T {
    when (this) {
        is List -> return this.single()
        else -> {
            val iterator = iterator()
            if (!iterator.hasNext()) throw NoSuchElementException("Collection is empty.")
            val single = iterator.next()
            if (iterator.hasNext()) throw IllegalArgumentException("Collection has more than one element.")
            return single
        }
    }
}

public inline fun <T> Iterable<T>.single(predicate: (T) -> Boolean): T {
    var single: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Collection contains more than one matching element.")
            single = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return single as T
}

public fun <T> Iterable<T>.singleOrNull(): T? {
    when (this) {
        is List -> return this.singleOrNull()
        else -> {
            val iterator = iterator()
            if (!iterator.hasNext()) return null
            val single = iterator.next()
            if (iterator.hasNext()) return null
            return single
        }
    }
}

public inline fun <T> Iterable<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var single: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) return null
            single = element
            found = true
        }
    }
    if (!found) return null
    return single
}

public fun <T> Iterable<T>.any(): Boolean {
    for (element in this) return true
    return false
}

public fun <T> Iterable<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

public fun <T> Iterable<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

public fun <T> Iterable<T>.count(): Int {
    if (this is Collection<*>) return (this as Collection<*>).size

    var count = 0
    for (element in this) {
        count += 1
        if (count < 0) throw ArithmeticException("Count overflow has happened.")
    }
    return count
}

public inline fun <T> Iterable<T>.count(predicate: (T) -> Boolean): Int {
    if (this is Collection<*> && (this as Collection<*>).isEmpty()) return 0

    var count = 0
    for (element in this) {
        if (predicate(element)) {
            count += 1
            if (count < 0) throw ArithmeticException("Count overflow has happened.")
        }
    }
    return count
}

// KSP-979: Keep the Iterable index family on the iterator-backed source path.
// The counter is checked after the previous increment wraps negative, allowing
// the candidate at Int.MAX_VALUE to be evaluated before the next iteration
// reports overflow, matching the Kotlin stdlib contract.
public fun <T> Iterable<T>.indexOf(element: T): Int {
    var index = 0
    for (item in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        if (element == item) return index
        index++
    }
    return -1
}

public inline fun <T> Iterable<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    var index = 0
    for (item in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        if (predicate(item)) return index
        index++
    }
    return -1
}

public inline fun <T> Iterable<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    var lastIndex = -1
    var index = 0
    for (item in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        if (predicate(item)) lastIndex = index
        index++
    }
    return lastIndex
}

@SinceKotlin("1.5")
public inline fun <T, R : Any> Iterable<T>.firstNotNullOfOrNull(transform: (T) -> R?): R? {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    return null
}

@SinceKotlin("1.5")
public inline fun <T, R : Any> Iterable<T>.firstNotNullOf(transform: (T) -> R?): R {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    throw NoSuchElementException("No element of the collection was transformed to a non-null value.")
}

@Suppress("UNCHECKED_CAST")
public fun <T : Any> Iterable<T?>.requireNoNulls(): Iterable<T> {
    for (element in this) {
        if (element == null) {
            throw IllegalArgumentException("null element found in $this.")
        }
    }
    return this as Iterable<T>
}

// Shared by Iterable.joinTo/joinToString (below) and Sequence.joinTo/joinToString
// (SequenceAggregateHOF.kt, kotlin.sequences) — both only need iterator(), so a
// single implementation keyed on Iterator<T> covers both receiver types (KSP-621).
internal fun <T> appendJoinToPlain(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(element.toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

internal fun <T> appendJoinToTransform(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(transform(element).toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, -1, "...")

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, limit, truncated)

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder = appendJoinToTransform(this.iterator(), buffer, separator, prefix, postfix, limit, truncated, transform)

public fun <T> Iterable<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...").toString()

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated).toString()

// The `transform` overloads are spelled per arity because a trailing lambda
// cannot be bound to the defaulted `String` parameters above.
public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String {
    return appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...", transform).toString()
}

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    transform: (T) -> Any
): String = joinToString(separator, prefix, "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    transform: (T) -> Any
): String = joinToString(separator, "", "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated, transform).toString()

// KSP-632: remaining Iterable HOFs migrated from the Swift runtime `kk_list_*`
// bridges. These implementations rely only on `iterator()` / `toMutableList()`,
// so they work for List, Set and any other Iterable.

public fun <T> Iterable<T>.reduceRight(operation: (T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexed(operation: (Int, T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightOrNull(operation: (T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexedOrNull(operation: (Int, T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

// KSP-993: Iterable sorting remains source-backed and materializes exactly
// once before applying stable in-place sorting to the mutable result.
public fun <T : Comparable<T>> Iterable<T>.sorted(): List<T> {
    val result = toMutableList()
    var i = 0
    while (i < result.size - 1) {
        var j = 0
        while (j < result.size - i - 1) {
            if (compareValues(result[j + 1], result[j]) < 0) {
                val tmp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = tmp
            }
            j++
        }
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> Iterable<T>.sortedBy(crossinline selector: (T) -> R?): List<T> {
    val result = toMutableList()
    var i = 0
    while (i < result.size - 1) {
        var j = 0
        while (j < result.size - i - 1) {
            if (compareValues(selector(result[j + 1]), selector(result[j])) < 0) {
                val tmp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = tmp
            }
            j++
        }
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> Iterable<T>.sortedByDescending(crossinline selector: (T) -> R?): List<T> {
    val result = toMutableList()
    var i = 0
    while (i < result.size - 1) {
        var j = 0
        while (j < result.size - i - 1) {
            if (compareValues(selector(result[j + 1]), selector(result[j])) > 0) {
                val tmp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = tmp
            }
            j++
        }
        i++
    }
    return result
}

public fun <T : Comparable<T>> Iterable<T>.sortedDescending(): List<T> {
    return sortedWith(reverseOrder())
}

public fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = toMutableList()
    var i = 0
    while (i < result.size - 1) {
        var j = 0
        while (j < result.size - i - 1) {
            if (comparator.compare(result[j + 1], result[j]) < 0) {
                val tmp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = tmp
            }
            j++
        }
        i++
    }
    return result
}

public fun <T> Iterable<T>.joinToString(
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), ", ", "", "", -1, "...", transform).toString()

// Char.toString() is represented by its numeric code in the generic path;
// keep the List<Char> overload aligned with Kotlin's character rendering.
public fun List<Char>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    var first = true
    for (element in this) {
        if (!first) buffer.append(separator)
        buffer.append(element)
        first = false
    }
    buffer.append(postfix)
    return buffer.toString()
}

// KSP-976: Iterable fold-family source bodies preserve the generic accumulator
// type while traversing every receiver through its iterator exactly once.
public inline fun <T, R> Iterable<T>.fold(initial: R, operation: (acc: R, T) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public inline fun <T, R> Iterable<T>.foldIndexed(initial: R, operation: (index: Int, acc: R, T) -> R): R {
    var index = 0
    var accumulator = initial
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        accumulator = operation(index, accumulator, element)
        index += 1
    }
    return accumulator
}

// KSP-983: Iterable max-family APIs migrated from the Kotlin 2.3.10 stdlib.

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Iterable<Double>.max(): Double {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        max = kk_max_double(max, e)
    }
    return max
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Iterable<Float>.max(): Float {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        max = kk_max_float(max, e)
    }
    return max
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun <T : Comparable<T>> Iterable<T>.max(): T {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        if (max < e) max = e
    }
    return max
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxByOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public inline fun <T, R : Comparable<R>> Iterable<T>.maxBy(selector: (T) -> R): T {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxElem = iterator.next()
    if (!iterator.hasNext()) return maxElem
    var maxValue = selector(maxElem)
    do {
        val e = iterator.next()
        val v = selector(e)
        if (maxValue < v) {
            maxElem = e
            maxValue = v
        }
    } while (iterator.hasNext())
    return maxElem
}

@SinceKotlin("1.4")
public inline fun <T, R : Comparable<R>> Iterable<T>.maxByOrNull(selector: (T) -> R): T? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var maxElem = iterator.next()
    if (!iterator.hasNext()) return maxElem
    var maxValue = selector(maxElem)
    do {
        val e = iterator.next()
        val v = selector(e)
        if (maxValue < v) {
            maxElem = e
            maxValue = v
        }
    } while (iterator.hasNext())
    return maxElem
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Iterable<T>.maxOf(selector: (T) -> Double): Double {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = kk_unbox_double(selector(iterator.next()))
    while (iterator.hasNext()) {
        val v = kk_unbox_double(selector(iterator.next()))
        maxValue = kk_max_double(maxValue, v)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Iterable<T>.maxOf(selector: (T) -> Float): Float {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = kk_unbox_float(selector(iterator.next()))
    while (iterator.hasNext()) {
        val v = kk_unbox_float(selector(iterator.next()))
        maxValue = kk_max_float(maxValue, v)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Iterable<T>.maxOf(selector: (T) -> R): R {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val v = selector(iterator.next())
        if (maxValue < v) maxValue = v
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Iterable<T>.maxOfOrNull(selector: (T) -> Double): Double? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var maxValue = kk_unbox_double(selector(iterator.next()))
    while (iterator.hasNext()) {
        val v = kk_unbox_double(selector(iterator.next()))
        maxValue = kk_max_double(maxValue, v)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Iterable<T>.maxOfOrNull(selector: (T) -> Float): Float? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var maxValue = kk_unbox_float(selector(iterator.next()))
    while (iterator.hasNext()) {
        val v = kk_unbox_float(selector(iterator.next()))
        maxValue = kk_max_float(maxValue, v)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Iterable<T>.maxOfOrNull(selector: (T) -> R): R? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val v = selector(iterator.next())
        if (maxValue < v) maxValue = v
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.maxOfWith(comparator: Comparator<in R>, selector: (T) -> R): R {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val v = selector(iterator.next())
        if (comparator.compare(maxValue, v) < 0) maxValue = v
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.maxOfWithOrNull(comparator: Comparator<in R>, selector: (T) -> R): R? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val v = selector(iterator.next())
        if (comparator.compare(maxValue, v) < 0) maxValue = v
    }
    return maxValue
}

@SinceKotlin("1.4")
public fun Iterable<Double>.maxOrNull(): Double? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        max = kk_max_double(max, e)
    }
    return max
}

@SinceKotlin("1.4")
public fun Iterable<Float>.maxOrNull(): Float? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        max = kk_max_float(max, e)
    }
    return max
}

@SinceKotlin("1.4")
public fun <T : Comparable<T>> Iterable<T>.maxOrNull(): T? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        if (max < e) max = e
    }
    return max
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxWithOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun <T> Iterable<T>.maxWith(comparator: Comparator<in T>): T {
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        if (comparator.compare(max, e) < 0) max = e
    }
    return max
}

@SinceKotlin("1.4")
public fun <T> Iterable<T>.maxWithOrNull(comparator: Comparator<in T>): T? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) {
        val e = iterator.next()
        if (comparator.compare(max, e) < 0) max = e
    }
    return max
}
