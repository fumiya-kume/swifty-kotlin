package kotlin.text

// CharSequence.chunked(size, transform) / .windowed(size, step, partialWindows, transform) —
// the List<R>-returning overloads, as opposed to the already-migrated chunkedSequence /
// windowedSequence — are bundled Kotlin source rather than native ABI bridges. The public
// chunked overload is self-contained because forwarding its function parameter to another
// generic bundled-source function currently has a KIR reachability gap. The windowed trailing-
// lambda path retains a uniquely named helper while that legacy route remains.
// Indices use the CharSequence.length interface property so that String and other
// CharSequence implementations observe their character count without materializing the
// receiver.
//
// Unlike ListWindowChunk.kt, `chunked` does NOT delegate to `windowed` here (real kotlinc's
// own stdlib does: `chunked(size, transform) = windowed(size, size, true, transform)`) — a
// generic bundled-source function forwarding its own function-typed parameter to another
// generic bundled-source function fails to link (KIR call lowering never discovers the callee
// as reachable and never emits its body; confirmed independent of these two functions with a
// minimal two-function repro). Each function is self-contained until that's root-caused.
//
// The loop keeps advancing by `step` while `index < length` alone (not stopping at the first
// partial/short window): when `step` is smaller than `size`, more than one trailing partial
// window can occur (e.g. "hi".windowed(100, 1, true) is [2, 1], not just [2]) — matches real
// kotlinc's `while (index in 0 until thisSize)` shape.

internal fun <R> CharSequence.kswiftkWindowedTransform(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (CharSequence) -> R
): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    val length = this.length
    val result = ArrayList<R>()
    var index = 0
    while (index < length) {
        val end = index + size
        if (end > length) {
            if (partialWindows) {
                result.add(transform(this.subSequence(index, length)))
            }
        } else {
            result.add(transform(this.subSequence(index, end)))
        }
        index += step
    }
    return result
}

// CharSequence chunked/windowed/zip APIs are implemented in bundled Kotlin
// source. Character indices use the receiver's length and indexed access so
// that UTF-8 storage details do not leak into the public Kotlin behavior.

private fun charSequenceWindow(source: CharSequence, start: Int, end: Int): String =
    source.subSequence(start, end).toString()

public fun CharSequence.chunked(size: Int): List<String> {
    require(size > 0) { "size must be positive, but was $size" }
    val length = this.length
    val result = mutableListOf<String>()
    var index = 0
    while (index < length) {
        val end = if (index + size < length) index + size else length
        result.add(charSequenceWindow(this, index, end))
        index += size
    }
    return result
}

public fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> {
    require(size > 0) { "size $size must be greater than zero." }
    val length = this.length
    val result = ArrayList<R>()
    var index = 0
    while (index < length) {
        val end = index + size
        val coercedEnd = if (end < 0 || end > length) length else end
        result.add(transform(this.subSequence(index, coercedEnd)))
        index += size
    }
    return result
}

public fun CharSequence.chunkedSequence(size: Int): Sequence<String> {
    require(size > 0) { "size must be positive, but was $size" }
    val source = this
    val length = source.length
    return object : Sequence<String> {
        override fun iterator(): Iterator<String> = object : Iterator<String> {
            var index = 0

            override fun hasNext(): Boolean = index < length

            override fun next(): String {
                if (!hasNext()) throw NoSuchElementException()
                val end = if (index + size < length) index + size else length
                val result = charSequenceWindow(source, index, end)
                index += size
                return result
            }
        }
    }
}

public fun <R> CharSequence.chunkedSequence(
    size: Int,
    transform: (CharSequence) -> R
): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    val source = this
    val length = source.length
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            var index = 0

            override fun hasNext(): Boolean = index < length

            override fun next(): R {
                if (!hasNext()) throw NoSuchElementException()
                val end = if (index + size < length) index + size else length
                val result = transform(charSequenceWindow(source, index, end))
                index += size
                return result
            }
        }
    }
}

public fun CharSequence.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): List<String> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    val length = this.length
    val result = mutableListOf<String>()
    var index = 0
    while (index < length) {
        val end = if (index + size < length) index + size else length
        if (end - index == size || partialWindows) {
            result.add(charSequenceWindow(this, index, end))
        }
        index += step
    }
    return result
}

public fun CharSequence.windowedSequence(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): Sequence<String> =
    this.windowedSequence(size, step, partialWindows) { it.toString() }

public fun <R> CharSequence.windowedSequence(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (CharSequence) -> R
): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    val source = this
    val length = source.length
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            var index = 0

            private fun hasWindow(): Boolean {
                if (index >= length) return false
                return partialWindows || index + size <= length
            }

            override fun hasNext(): Boolean = hasWindow()

            override fun next(): R {
                if (!hasWindow()) throw NoSuchElementException()
                val end = if (index + size < length) index + size else length
                val result = transform(charSequenceWindow(source, index, end))
                index += step
                return result
            }
        }
    }
}

public fun CharSequence.zip(other: CharSequence): List<Pair<Char, Char>> {
    val sourceLength = this.length
    val otherLength = other.length
    val result = mutableListOf<Pair<Char, Char>>()
    var index = 0
    while (index < sourceLength && index < otherLength) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public fun <R> CharSequence.zip(
    other: CharSequence,
    transform: (Char, Char) -> R
): List<R> {
    val sourceLength = this.length
    val otherLength = other.length
    val result = mutableListOf<R>()
    var index = 0
    while (index < sourceLength && index < otherLength) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public fun CharSequence.zipWithNext(): List<Pair<Char, Char>> {
    val length = this.length
    val result = mutableListOf<Pair<Char, Char>>()
    var index = 0
    while (index + 1 < length) {
        result.add(Pair(this[index], this[index + 1]))
        index++
    }
    return result
}

public fun <R> CharSequence.zipWithNext(transform: (Char, Char) -> R): List<R> {
    val length = this.length
    val result = mutableListOf<R>()
    var index = 0
    while (index + 1 < length) {
        result.add(transform(this[index], this[index + 1]))
        index++
    }
    return result
}
