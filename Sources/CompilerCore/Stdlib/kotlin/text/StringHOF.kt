package kotlin.text

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract

// MIGRATION-TEXT-008 / KSP-410
// String higher-order functions migrated from Swift runtime (RuntimeStringHOF.swift).
//
// BUG-174 is fixed (PR #5442, #5636): named labels in function-type parameters are
// now parsed correctly, so the upstream stdlib's documentation-only labels
// (`acc:`, `index:`) are restored below.
//
// BUG-175: none of the functions here return a bare, unbounded generic `R`
// inferred from a nullable-returning (`R?`) lambda body shaped like
// `{ x -> if (cond) y else null }` without an explicit type argument or
// expected type at the call site — mapNotNull/firstNotNullOf/
// firstNotNullOfOrNull hit "Type constraint could not be satisfied" with
// that exact (very common) call shape and stay Swift-side too. The
// already-shipped `List<T>.mapNotNull` (two type parameters, `T` fixed from
// the receiver) is unaffected, so this looks specific to inferring a *lone*
// type parameter purely from a nullable lambda return. See TODO.md BUG-175
// for the minimal repro.
//
// BUG-176: map/mapIndexed stay Swift-side (RuntimeStringHOF.swift) — NOT
// because of BUG-174, but because a bundled function of shape
// `fun <R> X.f(transform: (Char) -> R): List<R>` silently returns the WRONG
// VALUES (raw unboxed scalars instead of boxed elements, e.g.
// `"abc".map { it }` prints `[97, 98, 99]` instead of `[a, b, c]`) whenever
// `R` resolves concretely to `Char` or `Boolean` (confirmed both by
// inference and by explicit `<Char>` type argument; `<Any>` at the same
// call site is unaffected). The bug reproduces with ANY receiver type
// (String, CharArray — not String-specific) and is isolated to storing the
// transform's result into a `List<R>`: the identical accumulator shape
// (`fold`/`reduce`, where `R` is returned bare rather than stored in a
// list) is unaffected. This is silent data corruption, not a compile/link
// failure, so unlike BUG-174 it cannot be avoided by a source-level
// workaround in this file (the bad unbox is baked into the lambda's own
// compiled body by ABI lowering, before `map` ever sees the value). See
// TODO.md BUG-176 for the minimal repro.
//
// CharSequence-receiver functions read the interface property directly. The
// compiler preserves the receiver's runtime representation at the interface
// boundary and dispatches `length` through the CharSequence itable, so the
// length reads in these loops work for String, StringBuilder, and user-defined
// CharSequence classes. Other CharSequence operations retain their own
// runtime/itable contracts.

public fun String.filter(predicate: (Char) -> Boolean): String {
    val sb = StringBuilder()
    var i = 0
    val sz = length
    while (i < sz) {
        val c = this[i]
        if (predicate(c)) sb.append(c)
        i++
    }
    return sb.toString()
}

public fun String.filterNot(predicate: (Char) -> Boolean): String {
    val sb = StringBuilder()
    var i = 0
    val sz = length
    while (i < sz) {
        val c = this[i]
        if (!predicate(c)) sb.append(c)
        i++
    }
    return sb.toString()
}

public inline fun CharSequence.filter(predicate: (Char) -> Boolean): CharSequence {
    val sb = StringBuilder()
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(c)) sb.append(c)
        i++
    }
    return sb.toString()
}

public inline fun CharSequence.filterIndexed(predicate: (index: Int, Char) -> Boolean): CharSequence {
    val sb = StringBuilder()
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(i, c)) sb.append(c)
        i++
    }
    return sb.toString()
}

public inline fun String.filterIndexed(predicate: (index: Int, Char) -> Boolean): String {
    val sb = StringBuilder()
    var i = 0
    val sz = length
    while (i < sz) {
        val c = this[i]
        if (predicate(i, c)) sb.append(c)
        i++
    }
    return sb.toString()
}

@IgnorableReturnValue
public inline fun <C : Appendable> CharSequence.filterIndexedTo(
    destination: C,
    predicate: (index: Int, Char) -> Boolean
): C {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(i, c)) destination.append(c)
        i++
    }
    return destination
}

public inline fun CharSequence.filterNot(predicate: (Char) -> Boolean): CharSequence {
    val sb = StringBuilder()
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (!predicate(c)) sb.append(c)
        i++
    }
    return sb.toString()
}

@IgnorableReturnValue
public inline fun <C : Appendable> CharSequence.filterNotTo(
    destination: C,
    predicate: (Char) -> Boolean
): C {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (!predicate(c)) destination.append(c)
        i++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <C : Appendable> CharSequence.filterTo(
    destination: C,
    predicate: (Char) -> Boolean
): C {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(c)) destination.append(c)
        i++
    }
    return destination
}

public fun <R> CharSequence.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.length
    while (i < sz) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <R> CharSequence.mapIndexed(transform: (Int, Char) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.length
    while (i < sz) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public inline fun <R : Any> CharSequence.mapIndexedNotNull(transform: (index: Int, Char) -> R?): List<R> {
    return mapIndexedNotNullTo(ArrayList<R>(), transform)
}

@IgnorableReturnValue
public inline fun <R : Any, C : MutableCollection<in R>> CharSequence.mapIndexedNotNullTo(
    destination: C,
    transform: (index: Int, Char) -> R?
): C {
    var index = 0
    while (index < this.length) {
        val transformed = transform(index, this[index])
        if (transformed != null) destination.add(transformed)
        index++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <R, C : MutableCollection<in R>> CharSequence.mapIndexedTo(
    destination: C,
    transform: (index: Int, Char) -> R
): C {
    var index = 0
    while (index < this.length) {
        destination.add(transform(index, this[index]))
        index++
    }
    return destination
}

public fun <R : Any> CharSequence.mapNotNull(transform: (Char) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.length
    while (i < sz) {
        val transformed = transform(this[i])
        if (transformed != null) result.add(transformed)
        i++
    }
    return result
}

@IgnorableReturnValue
public inline fun <R : Any, C : MutableCollection<in R>> CharSequence.mapNotNullTo(
    destination: C,
    transform: (Char) -> R?
): C {
    var index = 0
    while (index < this.length) {
        val transformed = transform(this[index])
        if (transformed != null) destination.add(transformed)
        index++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <R, C : MutableCollection<in R>> CharSequence.mapTo(
    destination: C,
    transform: (Char) -> R
): C {
    var index = 0
    while (index < this.length) {
        destination.add(transform(this[index]))
        index++
    }
    return destination
}

/**
 * Returns a single list of all elements yielded from results of [transform] function being invoked on each character of original char sequence.
 */
public inline fun <R> CharSequence.flatMap(transform: (Char) -> Iterable<R>): List<R> {
    return flatMapTo(ArrayList<R>(), transform)
}

/**
 * Returns a single list of all elements yielded from results of [transform] function being invoked on each character
 * and its index in the original char sequence.
 */
@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterable")
@kotlin.internal.InlineOnly
public inline fun <R> CharSequence.flatMapIndexed(transform: (index: Int, Char) -> Iterable<R>): List<R> {
    return flatMapIndexedTo(ArrayList<R>(), transform)
}

/**
 * Appends all elements yielded from results of [transform] function being invoked on each character
 * and its index in the original char sequence, to the given [destination].
 */
@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterableTo")
@IgnorableReturnValue
@kotlin.internal.InlineOnly
public inline fun <R, C : MutableCollection<in R>> CharSequence.flatMapIndexedTo(
    destination: C,
    transform: (index: Int, Char) -> Iterable<R>
): C {
    var index = 0
    while (index < this.length) {
        val list = transform(index, this[index])
        index++
        val resultIterator = list.iterator()
        while (resultIterator.hasNext()) destination.add(resultIterator.next())
    }
    return destination
}

/**
 * Appends all elements yielded from results of [transform] function being invoked on each character of original char sequence, to the given [destination].
 */
@IgnorableReturnValue
public inline fun <R, C : MutableCollection<in R>> CharSequence.flatMapTo(
    destination: C,
    transform: (Char) -> Iterable<R>
): C {
    var index = 0
    while (index < this.length) {
        val list = transform(this[index])
        index++
        val resultIterator = list.iterator()
        while (resultIterator.hasNext()) destination.add(resultIterator.next())
    }
    return destination
}

@kotlin.internal.InlineOnly
public inline fun CharSequence.elementAt(index: Int): Char = get(index)

@kotlin.internal.InlineOnly
@OptIn(kotlin.contracts.ExperimentalContracts::class)
public inline fun CharSequence.elementAtOrElse(index: Int, defaultValue: (Int) -> Char): Char {
    contract {
        callsInPlace(defaultValue, InvocationKind.AT_MOST_ONCE)
    }
    return if (index >= 0 && index < length) get(index) else defaultValue(index)
}

@kotlin.internal.InlineOnly
public inline fun CharSequence.elementAtOrNull(index: Int): Char? =
    if (index >= 0 && index < length) get(index) else null

public fun <R : Any> CharSequence.firstNotNullOf(transform: (Char) -> R?): R {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val transformed = transform(this[i])
        if (transformed != null) return transformed
        i++
    }
    throw NoSuchElementException("No element of the char sequence was transformed to a non-null value.")
}

public fun CharSequence.first(): Char {
    if (isEmpty())
        throw NoSuchElementException("Char sequence is empty.")
    return this[0]
}

public inline fun CharSequence.first(predicate: (Char) -> Boolean): Char {
    var index = 0
    while (index < length) {
        val element = this[index]
        if (predicate(element)) return element
        index++
    }
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun <R : Any> CharSequence.firstNotNullOfOrNull(transform: (Char) -> R?): R? {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val transformed = transform(this[i])
        if (transformed != null) return transformed
        i++
    }
    return null
}

public fun CharSequence.firstOrNull(): Char? {
    return if (isEmpty()) null else this[0]
}

public inline fun CharSequence.firstOrNull(predicate: (Char) -> Boolean): Char? {
    var index = 0
    while (index < length) {
        val element = this[index]
        if (predicate(element)) return element
        index++
    }
    return null
}

public fun CharSequence.any(): Boolean {
    return !isEmpty()
}

public fun CharSequence.any(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    val sz = this.length
    while (i < sz) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun CharSequence.all(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    val sz = this.length
    while (i < sz) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun CharSequence.none(predicate: (Char) -> Boolean): Boolean {
    var i = 0
    val sz = this.length
    while (i < sz) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun CharSequence.count(predicate: (Char) -> Boolean): Int {
    var count = 0
    var i = 0
    val sz = this.length
    while (i < sz) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}

public fun CharSequence.find(predicate: (Char) -> Boolean): Char? {
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(c)) return c
        i++
    }
    return null
}

public fun CharSequence.findLast(predicate: (Char) -> Boolean): Char? {
    var i = this.length - 1
    while (i >= 0) {
        val c = this[i]
        if (predicate(c)) return c
        i--
    }
    return null
}

public fun String.onEach(action: (Char) -> Unit): String {
    var i = 0
    val sz = length
    while (i < sz) {
        action(this[i])
        i++
    }
    return this
}

public fun CharSequence.partition(predicate: (Char) -> Boolean): Pair<String, String> {
    val matched = StringBuilder()
    val unmatched = StringBuilder()
    var i = 0
    val sz = this.length
    while (i < sz) {
        val c = this[i]
        if (predicate(c)) matched.append(c) else unmatched.append(c)
        i++
    }
    return Pair(matched.toString(), unmatched.toString())
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun CharSequence.sumBy(selector: (Char) -> Int): Int {
    var sum = 0
    var i = 0
    val sz = this.length
    while (i < sz) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun CharSequence.sumByDouble(selector: (Char) -> Double): Double {
    var sum = 0.0
    var i = 0
    val sz = this.length
    while (i < sz) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("sumOfDouble")
@kotlin.internal.InlineOnly
public inline fun CharSequence.sumOf(selector: (Char) -> Double): Double {
    var sum: Double = 0.toDouble()
    var i = 0
    while (i < this.length) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
@kotlin.jvm.JvmName("sumOfInt")
@kotlin.internal.InlineOnly
public inline fun CharSequence.sumOf(selector: (Char) -> Int): Int {
    var sum: Int = 0.toInt()
    var i = 0
    while (i < this.length) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("sumOfLong")
@kotlin.internal.InlineOnly
public inline fun CharSequence.sumOf(selector: (Char) -> Long): Long {
    var sum: Long = 0.toLong()
    var i = 0
    while (i < this.length) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.5")
@kotlin.jvm.JvmName("sumOfUInt")
@kotlin.internal.InlineOnly
public inline fun CharSequence.sumOf(selector: (Char) -> UInt): UInt {
    var sum: UInt = 0.toUInt()
    var i = 0
    while (i < this.length) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.5")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("sumOfULong")
@kotlin.internal.InlineOnly
public inline fun CharSequence.sumOf(selector: (Char) -> ULong): ULong {
    var sum: ULong = 0.toULong()
    var i = 0
    while (i < this.length) {
        sum += selector(this[i])
        i++
    }
    return sum
}

public fun String.onEachIndexed(action: (index: Int, Char) -> Unit): String {
    var i = 0
    val sz = length
    while (i < sz) {
        action(i, this[i])
        i++
    }
    return this
}

public fun CharSequence.reduce(operation: (acc: Char, Char) -> Char): Char {
    val sz = this.length
    if (sz == 0) throw UnsupportedOperationException("Empty char sequence can't be reduced.")
    var accumulator = this[0]
    var i = 1
    while (i < sz) {
        accumulator = operation(accumulator, this[i])
        i++
    }
    return accumulator
}

public fun CharSequence.reduceOrNull(operation: (acc: Char, Char) -> Char): Char? {
    val sz = this.length
    if (sz == 0) return null
    var accumulator = this[0]
    var i = 1
    while (i < sz) {
        accumulator = operation(accumulator, this[i])
        i++
    }
    return accumulator
}

public fun CharSequence.reduceIndexed(operation: (index: Int, acc: Char, Char) -> Char): Char {
    val sz = this.length
    if (sz == 0) throw UnsupportedOperationException("Empty char sequence can't be reduced.")
    var accumulator = this[0]
    var i = 1
    while (i < sz) {
        accumulator = operation(i, accumulator, this[i])
        i++
    }
    return accumulator
}

public fun CharSequence.reduceIndexedOrNull(operation: (index: Int, acc: Char, Char) -> Char): Char? {
    val sz = this.length
    if (sz == 0) return null
    var accumulator = this[0]
    var i = 1
    while (i < sz) {
        accumulator = operation(i, accumulator, this[i])
        i++
    }
    return accumulator
}

public fun CharSequence.reduceRight(operation: (Char, acc: Char) -> Char): Char {
    var i = this.length - 1
    if (i < 0) throw UnsupportedOperationException("Empty char sequence can't be reduced.")
    var accumulator = this[i]
    i--
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i--
    }
    return accumulator
}

public fun CharSequence.reduceRightOrNull(operation: (Char, acc: Char) -> Char): Char? {
    var i = this.length - 1
    if (i < 0) return null
    var accumulator = this[i]
    i--
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i--
    }
    return accumulator
}

public fun CharSequence.reduceRightIndexed(operation: (index: Int, Char, acc: Char) -> Char): Char {
    var i = this.length - 1
    if (i < 0) throw UnsupportedOperationException("Empty char sequence can't be reduced.")
    var accumulator = this[i]
    i--
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
        i--
    }
    return accumulator
}

public fun CharSequence.reduceRightIndexedOrNull(operation: (index: Int, Char, acc: Char) -> Char): Char? {
    var i = this.length - 1
    if (i < 0) return null
    var accumulator = this[i]
    i--
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
        i--
    }
    return accumulator
}

public fun <R> CharSequence.fold(initial: R, operation: (acc: R, Char) -> R): R {
    var accumulator = initial
    var i = 0
    val sz = this.length
    while (i < sz) {
        accumulator = operation(accumulator, this[i])
        i++
    }
    return accumulator
}

public fun <R> CharSequence.foldIndexed(initial: R, operation: (index: Int, acc: R, Char) -> R): R {
    var accumulator = initial
    var i = 0
    val sz = this.length
    while (i < sz) {
        accumulator = operation(i, accumulator, this[i])
        i++
    }
    return accumulator
}

public fun <R> CharSequence.foldRight(initial: R, operation: (Char, acc: R) -> R): R {
    var accumulator = initial
    var i = this.length - 1
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i--
    }
    return accumulator
}

public fun <R> CharSequence.foldRightIndexed(initial: R, operation: (index: Int, Char, acc: R) -> R): R {
    var accumulator = initial
    var i = this.length - 1
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
        i--
    }
    return accumulator
}

// KSP-1366: CharSequence association functions are source-backed. The
// explicit index walk keeps CharSequence receiver dispatch and the source
// implementation visible to the compiler while matching the standard map
// capacity and dynamic length behavior.
public inline fun <K, V> CharSequence.associate(transform: (Char) -> Pair<K, V>): Map<K, V> {
    val result = LinkedHashMap<K, V>(mapCapacity(this.length).coerceAtLeast(16))
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        val pair = transform(e)
        result[pair.first] = pair.second
        i++
    }
    return result as Map<K, V>
}

public inline fun <K> CharSequence.associateBy(keySelector: (Char) -> K): Map<K, Char> {
    val result = LinkedHashMap<K, Char>(mapCapacity(this.length).coerceAtLeast(16))
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        result[keySelector(e)] = e
        i++
    }
    return result as Map<K, Char>
}

public inline fun <K, V> CharSequence.associateBy(
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): Map<K, V> {
    val result = LinkedHashMap<K, V>(mapCapacity(this.length).coerceAtLeast(16))
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        result[keySelector(e)] = valueTransform(e)
        i++
    }
    return result as Map<K, V>
}

@IgnorableReturnValue
public inline fun <K, M : MutableMap<in K, in Char>> CharSequence.associateByTo(
    destination: M,
    keySelector: (Char) -> K
): M {
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        destination.put(keySelector(e), e)
        i++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, in V>> CharSequence.associateByTo(
    destination: M,
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): M {
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        destination.put(keySelector(e), valueTransform(e))
        i++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, in V>> CharSequence.associateTo(
    destination: M,
    transform: (Char) -> Pair<K, V>
): M {
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        val pair = transform(e)
        destination.put(pair.first, pair.second)
        i++
    }
    return destination
}

@SinceKotlin("1.3")
public inline fun <V> CharSequence.associateWith(valueSelector: (Char) -> V): Map<Char, V> {
    val result = LinkedHashMap<Char, V>(
        mapCapacity(this.length.coerceAtMost(128)).coerceAtLeast(16)
    )
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        result[e] = valueSelector(e)
        i++
    }
    return result as Map<Char, V>
}

@SinceKotlin("1.3")
@IgnorableReturnValue
public inline fun <V, M : MutableMap<in Char, in V>> CharSequence.associateWithTo(
    destination: M,
    valueSelector: (Char) -> V
): M {
    var i = 0
    while (i < this.length) {
        val e: Char = this[i]
        destination.put(e, valueSelector(e))
        i++
    }
    return destination
}

// KSP-1379: CharSequence grouping functions are source-backed. The explicit
// index walk preserves the source receiver contract while avoiding iterator
// inference gaps in the bundled compiler.
public inline fun <K> CharSequence.groupBy(keySelector: (Char) -> K): Map<K, List<Char>> {
    val result = mutableMapOf<K, MutableList<Char>>()
    var i = 0
    while (i < this.length) {
        val element: Char = this[i]
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Char>()
            result[key] = bucket
            bucket.add(element)
        } else {
            existing.add(element)
        }
        i++
    }
    return result as Map<K, List<Char>>
}

public inline fun <K, V> CharSequence.groupBy(
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    var i = 0
    while (i < this.length) {
        val element: Char = this[i]
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            result[key] = bucket
            bucket.add(valueTransform(element))
        } else {
            existing.add(valueTransform(element))
        }
        i++
    }
    return result as Map<K, List<V>>
}

@IgnorableReturnValue
public inline fun <K, M : MutableMap<in K, MutableList<Char>>> CharSequence.groupByTo(
    destination: M,
    keySelector: (Char) -> K
): M {
    var i = 0
    while (i < this.length) {
        val element: Char = this[i]
        val key = keySelector(element)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<Char>()
            destination[key] = bucket
            bucket.add(element)
        } else {
            existing.add(element)
        }
        i++
    }
    return destination
}

@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, MutableList<V>>> CharSequence.groupByTo(
    destination: M,
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): M {
    var i = 0
    while (i < this.length) {
        val element: Char = this[i]
        val key = keySelector(element)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            destination[key] = bucket
            bucket.add(valueTransform(element))
        } else {
            existing.add(valueTransform(element))
        }
        i++
    }
    return destination
}
