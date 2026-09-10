package kotlin.collections

// KSP-433: Array<T> transform HOFs are bundled Kotlin source. Primitive-array
// variants are defined in PrimitiveArrayHOF.kt.

public fun <T, R> Array<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <T, R> Array<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <T, R : Any> Array<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <T, R> Array<T>.flatMap(transform: (T) -> List<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val nested = transform(this[i])
        var j = 0
        val nestedSize = nested.size
        while (j < nestedSize) {
            result.add(nested[j])
            j++
        }
        i++
    }
    return result
}

public fun <T> Array<T>.forEach(action: (T) -> Unit) {
    var i = 0
    val sz = this.size
    while (i < sz) {
        action(this[i])
        i++
    }
}

// `joinTo` / `joinToString` delegate to the source-backed Iterable
// implementations so Array and List share one rendering path. Primitive
// arrays retain their type-aware synthetic bridges until KSP-687.

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder = this.toList().joinTo(buffer, separator, prefix, postfix)

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder = this.toList().joinTo(buffer, separator, prefix, postfix, limit, truncated)

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder = this.toList().joinTo(buffer, separator, prefix, postfix, limit, truncated) { transform(it).toString() }

public fun <T> Array<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = this.toList().joinToString(separator, prefix, postfix)

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): String = this.toList().joinToString(separator, prefix, postfix, limit, truncated)

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String = this.toList().joinToString(separator, prefix, postfix) { transform(it).toString() }

public fun <T> Array<T>.joinToString(transform: (T) -> Any): String =
    this.toList().joinToString { transform(it).toString() }

public fun <T> Array<T>.joinToString(separator: String, transform: (T) -> Any): String =
    this.toList().joinToString(separator) { transform(it).toString() }

public fun <T> Array<T>.joinToString(separator: String, prefix: String, transform: (T) -> Any): String =
    this.toList().joinToString(separator, prefix) { transform(it).toString() }

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): String = this.toList().joinToString(separator, prefix, postfix, limit, truncated) { transform(it).toString() }

public fun <T> Array<T>.asSequence(): Sequence<T> = this.toList().asSequence()
