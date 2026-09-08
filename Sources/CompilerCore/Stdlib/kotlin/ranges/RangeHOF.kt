@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002
// Range/Progression higher-order functions migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeRangeAndDispatch.swift, RuntimeRangeIntRangeHOF.swift,
//   RuntimeRangeLongRange.swift, RuntimeRangeSharedHOF.swift (kk_range_forEach,
//   kk_range_map, kk_range_filter, kk_range_toList; kk_long_range_* / kk_char_range_*
//   equivalents)
//
// NOTE: Range/Progression members that still use the hardcoded range dispatch remain
// separate from these canonical source definitions. Source-backed range HOFs are selected
// by CallTypeChecker+RangeMemberFallback.swift and preserved by the collection lowering
// pass, matching the migration pattern used by MIGRATION-RANGE-003 (RangeCoercion.kt)
// and MIGRATION-COL-002 (ListHOF.kt).
//
// The `first`, `last`, and `step` properties are intentionally NOT included here: they are
// constant-time field reads with no pure-Kotlin expression available (would
// require introducing new native bridge plumbing for zero behavioral change).
// `count()`, `sum()`, and `reversed()` are now included and wired to the shared
// `__kk_range_*` ABI surface.
//
// `count(predicate)` is intentionally NOT included: CallTypeChecker+RangeMemberFallback.swift's
// isValidRangeMemberArity() only accepts a 0-arg `count` for range-like receivers, and (as noted
// above) member resolution for such receivers never falls through to user-declared candidates --
// so a 1-arg overload here would be an uncallable, misleading declaration. Widening that arity
// allow-list is dispatch-wiring work, not a Kotlin-source migration.

// KSP-457: range random APIs are public Kotlin source wrappers around the
// runtime's retained random-engine primitives. The __kk_* names deliberately
// keep these bridges private to the bundled stdlib layer.
@KsSymbolName("__kk_range_random")
private external fun __kk_intRangeRandom(range: IntRange): Int

@KsSymbolName("__kk_range_random_random")
private external fun __kk_intRangeRandomRandom(range: IntRange, random: Random): Int

@KsSymbolName("__kk_range_randomOrNull")
private external fun __kk_intRangeRandomOrNull(range: IntRange): Int?

@KsSymbolName("__kk_range_randomOrNull_random")
private external fun __kk_intRangeRandomOrNullRandom(range: IntRange, random: Random): Int?

@KsSymbolName("__kk_long_range_random")
private external fun __kk_longRangeRandom(range: LongRange): Long

@KsSymbolName("__kk_long_range_random_random")
private external fun __kk_longRangeRandomRandom(range: LongRange, random: Random): Long

@KsSymbolName("__kk_long_range_randomOrNull")
private external fun __kk_longRangeRandomOrNull(range: LongRange): Long?

@KsSymbolName("__kk_long_range_randomOrNull_random")
private external fun __kk_longRangeRandomOrNullRandom(range: LongRange, random: Random): Long?

@KsSymbolName("__kk_char_range_random")
private external fun __kk_charRangeRandom(range: CharRange): Char

@KsSymbolName("__kk_char_range_random_random")
private external fun __kk_charRangeRandomRandom(range: CharRange, random: Random): Char

@KsSymbolName("__kk_char_range_randomOrNull")
private external fun __kk_charRangeRandomOrNull(range: CharRange): Char?

@KsSymbolName("__kk_char_range_randomOrNull_random")
private external fun __kk_charRangeRandomOrNullRandom(range: CharRange, random: Random): Char?

@KsSymbolName("__kk_uint_range_random")
private external fun __kk_uintRangeRandom(range: UIntRange): UInt

@KsSymbolName("__kk_uint_range_random_random")
private external fun __kk_uintRangeRandomRandom(range: UIntRange, random: Random): UInt

@KsSymbolName("__kk_uint_range_randomOrNull")
private external fun __kk_uintRangeRandomOrNull(range: UIntRange): UInt?

@KsSymbolName("__kk_uint_range_randomOrNull_random")
private external fun __kk_uintRangeRandomOrNullRandom(range: UIntRange, random: Random): UInt?

@KsSymbolName("__kk_ulong_range_random")
private external fun __kk_ulongRangeRandom(range: ULongRange): ULong

@KsSymbolName("__kk_ulong_range_random_random")
private external fun __kk_ulongRangeRandomRandom(range: ULongRange, random: Random): ULong

@KsSymbolName("__kk_ulong_range_randomOrNull")
private external fun __kk_ulongRangeRandomOrNull(range: ULongRange): ULong?

@KsSymbolName("__kk_ulong_range_randomOrNull_random")
private external fun __kk_ulongRangeRandomOrNullRandom(range: ULongRange, random: Random): ULong?

public fun IntRange.random(): Int = __kk_intRangeRandom(this)
public fun IntRange.random(random: Random): Int = __kk_intRangeRandomRandom(this, random)
public fun IntRange.randomOrNull(): Int? = __kk_intRangeRandomOrNull(this)
public fun IntRange.randomOrNull(random: Random): Int? = __kk_intRangeRandomOrNullRandom(this, random)

public fun LongRange.random(): Long = __kk_longRangeRandom(this)
public fun LongRange.random(random: Random): Long = __kk_longRangeRandomRandom(this, random)
public fun LongRange.randomOrNull(): Long? = __kk_longRangeRandomOrNull(this)
public fun LongRange.randomOrNull(random: Random): Long? = __kk_longRangeRandomOrNullRandom(this, random)

public fun CharRange.random(): Char = __kk_charRangeRandom(this)
public fun CharRange.random(random: Random): Char = __kk_charRangeRandomRandom(this, random)
public fun CharRange.randomOrNull(): Char? = __kk_charRangeRandomOrNull(this)
public fun CharRange.randomOrNull(random: Random): Char? = __kk_charRangeRandomOrNullRandom(this, random)

public fun UIntRange.random(): UInt = __kk_uintRangeRandom(this)
public fun UIntRange.random(random: Random): UInt = __kk_uintRangeRandomRandom(this, random)
public fun UIntRange.randomOrNull(): UInt? = __kk_uintRangeRandomOrNull(this)
public fun UIntRange.randomOrNull(random: Random): UInt? = __kk_uintRangeRandomOrNullRandom(this, random)

public fun ULongRange.random(): ULong = __kk_ulongRangeRandom(this)
public fun ULongRange.random(random: Random): ULong = __kk_ulongRangeRandomRandom(this, random)
public fun ULongRange.randomOrNull(): ULong? = __kk_ulongRangeRandomOrNull(this)
public fun ULongRange.randomOrNull(random: Random): ULong? = __kk_ulongRangeRandomOrNullRandom(this, random)

// MARK: - IntRange

public fun IntRange.forEach(action: (Int) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> IntRange.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun IntRange.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun IntRange.toList(): List<Int> {
    val result = mutableListOf<Int>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun IntRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun IntRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun IntRange.reversed(): IntRange

public fun IntRange.toIntArray(): IntArray = toList().toIntArray()

public fun IntRange.average(): Double {
    if (isEmpty()) return Double.NaN
    var sum = 0.0
    for (element in this) sum += element.toDouble()
    return sum / count()
}

public fun IntRange.sorted(): List<Int> = toList().sorted()

public fun IntRange.take(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun IntRange.drop(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun IntRange.filterNot(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) if (!predicate(element)) result.add(element)
    return result
}

public fun IntRange.filterIndexed(predicate: (Int, Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> IntRange.mapIndexed(transform: (Int, Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> IntRange.mapNotNull(transform: (Int) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun IntRange.reduce(operation: (Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun IntRange.reduceIndexed(operation: (Int, Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index++
    }
    return accumulator
}

public fun <R> IntRange.fold(initial: R, operation: (R, Int) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> IntRange.foldIndexed(initial: R, operation: (Int, R, Int) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun IntRange.find(predicate: (Int) -> Boolean): Int? = firstOrNull(predicate)
public fun IntRange.findLast(predicate: (Int) -> Boolean): Int? = lastOrNull(predicate)

public fun IntRange.first(predicate: (Int) -> Boolean): Int {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("No element found matching predicate.")
}

public fun IntRange.firstOrNull(): Int? = if (isEmpty()) null else first
public fun IntRange.firstOrNull(predicate: (Int) -> Boolean): Int? {
    for (element in this) if (predicate(element)) return element
    return null
}

@NoInline
public fun IntRange.last(predicate: (Int) -> Boolean): Int {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("No element found matching predicate.")
    return result
}

public fun IntRange.lastOrNull(): Int? = if (isEmpty()) null else last
@NoInline
public fun IntRange.lastOrNull(predicate: (Int) -> Boolean): Int? {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun IntRange.any(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun IntRange.none(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun IntRange.chunked(size: Int): List<List<Int>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    var current = mutableListOf<Int>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<Int>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun IntRange.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<Int>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<Int>()
        var j = i
        while (j < values.size && j < end) {
            window.add(values[j])
            j++
        }
        result.add(window)
        i += step
    }
    return result
}

// MARK: - IntProgression

public fun IntProgression.forEach(action: (Int) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> IntProgression.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun IntProgression.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun IntProgression.toList(): List<Int> {
    val result = mutableListOf<Int>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun IntProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun IntProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun IntProgression.reversed(): IntProgression

public fun IntProgression.toIntArray(): IntArray = toList().toIntArray()

public fun IntProgression.average(): Double {
    if (isEmpty()) return Double.NaN
    var sum = 0.0
    for (element in this) sum += element.toDouble()
    return sum / count()
}

public fun IntProgression.sorted(): List<Int> = toList().sorted()

public fun IntProgression.take(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun IntProgression.drop(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun IntProgression.filterNot(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) if (!predicate(element)) result.add(element)
    return result
}

public fun IntProgression.filterIndexed(predicate: (Int, Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> IntProgression.mapIndexed(transform: (Int, Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> IntProgression.mapNotNull(transform: (Int) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun IntProgression.reduce(operation: (Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun IntProgression.reduceIndexed(operation: (Int, Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index++
    }
    return accumulator
}

public fun <R> IntProgression.fold(initial: R, operation: (R, Int) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> IntProgression.foldIndexed(initial: R, operation: (Int, R, Int) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun IntProgression.find(predicate: (Int) -> Boolean): Int? = firstOrNull(predicate)
public fun IntProgression.findLast(predicate: (Int) -> Boolean): Int? = lastOrNull(predicate)

private fun intProgressionDescription(progression: IntProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun IntProgression.first(): Int {
    if (isEmpty())
        throw NoSuchElementException("Progression ${intProgressionDescription(this)} is empty.")
    return this.first
}

public fun IntProgression.first(predicate: (Int) -> Boolean): Int {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("No element found matching predicate.")
}

public fun IntProgression.firstOrNull(): Int? = if (isEmpty()) null else first
public fun IntProgression.firstOrNull(predicate: (Int) -> Boolean): Int? {
    for (element in this) if (predicate(element)) return element
    return null
}

@SinceKotlin("1.7")
public fun IntProgression.last(): Int {
    if (isEmpty())
        throw NoSuchElementException("Progression ${intProgressionDescription(this)} is empty.")
    return this.last
}

@NoInline
public fun IntProgression.last(predicate: (Int) -> Boolean): Int {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("No element found matching predicate.")
    return result
}

public fun IntProgression.lastOrNull(): Int? = if (isEmpty()) null else last
@NoInline
public fun IntProgression.lastOrNull(predicate: (Int) -> Boolean): Int? {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun IntProgression.any(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun IntProgression.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun IntProgression.none(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun IntProgression.chunked(size: Int): List<List<Int>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    var current = mutableListOf<Int>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<Int>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun IntProgression.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<Int>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<Int>()
        var j = i
        while (j < values.size && j < end) {
            window.add(values[j])
            j++
        }
        result.add(window)
        i += step
    }
    return result
}

// MARK: - LongRange

public fun LongRange.forEach(action: (Long) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> LongRange.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun LongRange.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun LongRange.toList(): List<Long> {
    val result = mutableListOf<Long>()
    if (step > 0L) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0L) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

public fun LongRange.take(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun LongRange.drop(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var skipped = 0
    for (element in this) {
        if (skipped < n) {
            skipped++
            continue
        }
        result.add(element)
    }
    return result
}

public fun LongRange.sorted(): List<Long> {
    return toList().sorted()
}

public fun LongRange.average(): Double {
    var sum = 0.0
    var count = 0
    for (element in this) {
        sum += element
        count++
    }
    return if (count > 0) sum / count else 0.0 / 0.0
}

@KsSymbolName("__kk_range_count")
public fun LongRange.count(): Int {
    val first = first.toLong()
    val last = last.toLong()
    val step = step.toLong()
    val count = if (step > 0L) {
        if (first > last) 0L else (last - first) / step + 1L
    } else if (step < 0L) {
        if (first < last) 0L else (first - last) / (-step) + 1L
    } else {
        0L
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun LongRange.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun LongRange.reversed(): LongProgression

// MARK: - LongProgression

private fun longProgressionDescription(progression: LongProgression): String {
    // Widen before negation so the existing Int-typed synthetic step also
    // renders Int.MIN_VALUE as 2147483648 when used in an empty message.
    val step = progression.step.toLong()
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun LongProgression.first(): Long {
    if (isEmpty())
        throw NoSuchElementException("Progression ${longProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun LongProgression.firstOrNull(): Long? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun LongProgression.last(): Long {
    if (isEmpty())
        throw NoSuchElementException("Progression ${longProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun LongProgression.lastOrNull(): Long? = if (isEmpty()) null else this.last

public fun LongProgression.forEach(action: (Long) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> LongProgression.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun LongProgression.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun LongProgression.toList(): List<Long> {
    val result = mutableListOf<Long>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

public fun LongProgression.take(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun LongProgression.drop(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var skipped = 0
    for (element in this) {
        if (skipped < n) {
            skipped++
            continue
        }
        result.add(element)
    }
    return result
}

public fun LongProgression.sorted(): List<Long> {
    return toList().sorted()
}

public fun LongProgression.average(): Double {
    var sum = 0.0
    var count = 0
    for (element in this) {
        sum += element
        count++
    }
    return if (count > 0) sum / count else 0.0 / 0.0
}

@KsSymbolName("__kk_range_count")
public fun LongProgression.count(): Int {
    val first = first.toLong()
    val last = last.toLong()
    val step = step.toLong()
    val count = if (step > 0L) {
        if (first > last) 0L else (last - first) / step + 1L
    } else if (step < 0L) {
        if (first < last) 0L else (first - last) / (-step) + 1L
    } else {
        0L
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun LongProgression.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun LongProgression.reversed(): LongProgression

// MARK: - CharRange

public fun CharRange.forEach(action: (Char) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> CharRange.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun CharRange.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun CharRange.toList(): List<Char> {
    val result = mutableListOf<Char>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

public fun CharRange.take(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun CharRange.drop(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
    var skipped = 0
    for (element in this) {
        if (skipped < n) {
            skipped++
            continue
        }
        result.add(element)
    }
    return result
}

public fun CharRange.sorted(): List<Char> {
    return toList().sorted()
}

@KsSymbolName("__kk_range_count")
public fun CharRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun CharRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun CharRange.reversed(): CharRange

// MARK: - CharProgression

private fun charProgressionDescription(progression: CharProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun CharProgression.first(): Char {
    if (isEmpty()) throw NoSuchElementException("Progression ${charProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun CharProgression.firstOrNull(): Char? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun CharProgression.last(): Char {
    if (isEmpty()) throw NoSuchElementException("Progression ${charProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun CharProgression.lastOrNull(): Char? = if (isEmpty()) null else this.last

public fun CharProgression.forEach(action: (Char) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> CharProgression.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun CharProgression.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun CharProgression.toList(): List<Char> {
    val result = mutableListOf<Char>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

public fun CharProgression.take(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun CharProgression.drop(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
    var skipped = 0
    for (element in this) {
        if (skipped < n) {
            skipped++
            continue
        }
        result.add(element)
    }
    return result
}

public fun CharProgression.sorted(): List<Char> {
    return toList().sorted()
}

@KsSymbolName("__kk_range_count")
public fun CharProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun CharProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun CharProgression.reversed(): CharProgression

// MARK: - UIntRange

public fun UIntRange.forEach(action: (UInt) -> Unit) {
    for (element in this) { action(element) }
}

public fun UIntRange.reduce(operation: (UInt, UInt) -> UInt): UInt {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun UIntRange.reduceIndexed(operation: (Int, UInt, UInt) -> UInt): UInt {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index++
    }
    return accumulator
}

public fun <R> UIntRange.fold(initial: R, operation: (R, UInt) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> UIntRange.foldIndexed(initial: R, operation: (Int, R, UInt) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun UIntRange.find(predicate: (UInt) -> Boolean): UInt? = firstOrNull(predicate)
public fun UIntRange.findLast(predicate: (UInt) -> Boolean): UInt? = lastOrNull(predicate)

public fun UIntRange.first(predicate: (UInt) -> Boolean): UInt {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun UIntRange.firstOrNull(predicate: (UInt) -> Boolean): UInt? {
    for (element in this) if (predicate(element)) return element
    return null
}

@NoInline
public fun UIntRange.last(predicate: (UInt) -> Boolean): UInt {
    var found = false
    var result = 0u
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return result
}

@NoInline
public fun UIntRange.lastOrNull(predicate: (UInt) -> Boolean): UInt? {
    var found = false
    var result = 0u
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun UIntRange.any(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun UIntRange.all(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun UIntRange.none(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun UIntRange.take(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun UIntRange.drop(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun UIntRange.chunked(size: Int): List<List<UInt>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    var current = mutableListOf<UInt>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<UInt>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun UIntRange.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<UInt>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<UInt>()
        var j = i
        while (j < values.size && j < end) {
            window.add(values[j])
            j++
        }
        result.add(window)
        i += step
    }
    return result
}

public fun <R> UIntRange.map(transform: (UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun UIntRange.filter(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun UIntRange.filterNot(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun UIntRange.filterIndexed(predicate: (Int, UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> UIntRange.mapIndexed(transform: (Int, UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> UIntRange.mapNotNull(transform: (UInt) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun UIntRange.toList(): List<UInt> {
    val result = mutableListOf<UInt>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun UIntRange.count(): Int {
    val count: UInt = if (step > 0) {
        if (first > last) 0u else (last - first) / step.toUInt() + 1u
    } else if (step < 0) {
        if (first < last) 0u else (first - last) / (-step).toUInt() + 1u
    } else {
        0u
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun UIntRange.sum(): UInt {
    var sum = 0u
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun UIntRange.reversed(): UIntProgression

// MARK: - UIntProgression

public fun UIntProgression.forEach(action: (UInt) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> UIntProgression.map(transform: (UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun UIntProgression.filter(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun UIntProgression.filterNot(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun UIntProgression.take(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun UIntProgression.drop(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun UIntProgression.chunked(size: Int): List<List<UInt>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    var current = mutableListOf<UInt>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<UInt>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun UIntProgression.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<UInt>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<UInt>()
        var j = i
        while (j < values.size && j < end) {
            window.add(values[j])
            j++
        }
        result.add(window)
        i += step
    }
    return result
}

public fun UIntProgression.filterIndexed(predicate: (Int, UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> UIntProgression.mapIndexed(transform: (Int, UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> UIntProgression.mapNotNull(transform: (UInt) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun UIntProgression.toList(): List<UInt> {
    val result = mutableListOf<UInt>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun UIntProgression.count(): Int {
    val count: UInt = if (step > 0) {
        if (first > last) 0u else (last - first) / step.toUInt() + 1u
    } else if (step < 0) {
        if (first < last) 0u else (first - last) / (-step).toUInt() + 1u
    } else {
        0u
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun UIntProgression.sum(): UInt {
    var sum = 0u
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun UIntProgression.reversed(): UIntProgression

// MARK: - ULongRange

public fun ULongRange.forEach(action: (ULong) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> ULongRange.map(transform: (ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun ULongRange.filter(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun ULongRange.toList(): List<ULong> {
    val result = mutableListOf<ULong>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun ULongRange.count(): Int {
    val count: ULong = if (step > 0) {
        if (first > last) 0uL else (last - first) / step.toULong() + 1uL
    } else if (step < 0) {
        if (first < last) 0uL else (first - last) / (-step).toULong() + 1uL
    } else {
        0uL
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun ULongRange.sum(): ULong {
    var sum = 0uL
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun ULongRange.reversed(): ULongProgression

// MARK: - ULongProgression

public fun ULongProgression.forEach(action: (ULong) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> ULongProgression.map(transform: (ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun ULongProgression.filter(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun ULongProgression.toList(): List<ULong> {
    val result = mutableListOf<ULong>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun ULongProgression.count(): Int {
    val count: ULong = if (step > 0) {
        if (first > last) 0uL else (last - first) / step.toULong() + 1uL
    } else if (step < 0) {
        if (first < last) 0uL else (first - last) / (-step).toULong() + 1uL
    } else {
        0uL
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun ULongProgression.sum(): ULong {
    var sum = 0uL
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun ULongProgression.reversed(): ULongProgression
