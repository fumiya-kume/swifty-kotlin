private class IndexedSequence(
    private val chars: CharArray,
    private val rendered: String
) : CharSequence {
    var lengthReads: Int = 0
    var getReads: Int = 0

    override val length: Int
        get() {
            lengthReads += 1
            return chars.size
        }

    override fun get(index: Int): Char {
        getReads += 1
        return chars[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        IndexedSequence(chars.copyOfRange(startIndex, endIndex), rendered)

    override fun toString(): String = rendered
}

private fun exceptionLabel(block: () -> Unit): String =
    try {
        block()
        "none"
    } catch (error: NoSuchElementException) {
        "NoSuchElementException:${error.message}"
    } catch (error: IllegalArgumentException) {
        "IllegalArgumentException:${error.message}"
    }

private fun directSingle(source: CharSequence): Char = source.single { it == 'b' }

private fun capturedSingleOrNull(source: CharSequence, wanted: Char): Char? =
    source.singleOrNull(predicate = { it == wanted })

private fun directNonLocal(source: CharSequence): Char {
    source.singleOrNull { return '!' }
    return '?'
}

private fun safeNonLocal(source: CharSequence?): Char {
    source?.singleOrNull { return '!' }
    return '?'
}

private fun capturedNonLocal(source: CharSequence, captured: Char): Char {
    source.singleOrNull { return captured }
    return '?'
}

private fun nullableNonLocal(source: CharSequence?, captured: Char): Char {
    source?.singleOrNull { return captured }
    return '?'
}

private fun discardedNonLocal(source: CharSequence): Char {
    source.singleOrNull { return '!' }
    return '?'
}

private fun nullableSingleOrNull(source: CharSequence?): Char? =
    source?.singleOrNull()

private fun nullableSingleOrNullPredicate(source: CharSequence?, wanted: Char): Char? =
    source?.singleOrNull { it == wanted }

fun main() {
    val customOne: CharSequence = IndexedSequence(charArrayOf('Z'), "wrong-custom-one")
    val customEmpty: CharSequence = IndexedSequence(charArrayOf(), "wrong-custom-empty")
    val customMultiple: CharSequence = IndexedSequence(charArrayOf('a', 'b'), "wrong-custom-multiple")

    println("single-custom=${customOne.single() == 'Z'}")
    println("single-custom-or-null=${customOne.singleOrNull() == 'Z'}")
    println("single-empty=${exceptionLabel { customEmpty.single() }}")
    println("single-multiple=${exceptionLabel { customMultiple.single() }}")
    println("single-or-null-empty=${customEmpty.singleOrNull() == null}")
    println("single-or-null-multiple=${customMultiple.singleOrNull() == null}")

    val customPredicate = IndexedSequence(charArrayOf('a', 'b', 'b'), "wrong-predicate")
    println("single-predicate-first=${exceptionLabel { customPredicate.single { it == 'b' } }}")
    println("single-predicate-counters=${customPredicate.lengthReads},${customPredicate.getReads}")

    val customPredicateOrNull = IndexedSequence(charArrayOf('a', 'b', 'b', 'c'), "wrong-predicate-null")
    println("single-or-null-predicate-second=${customPredicateOrNull.singleOrNull { it == 'b' } == null}")
    println("single-or-null-predicate-counters=${customPredicateOrNull.lengthReads},${customPredicateOrNull.getReads}")

    val noMatch = IndexedSequence(charArrayOf('a', 'c'), "wrong-no-match")
    println("single-predicate-none=${exceptionLabel { noMatch.single(predicate = { it == 'b' }) }}")
    println("single-or-null-predicate-none=${noMatch.singleOrNull { it == 'b' } == null}")

    val direct = IndexedSequence(charArrayOf('a', 'b'), "wrong-direct")
    println("direct=${directSingle(direct)}")
    println("captured=${capturedSingleOrNull(IndexedSequence(charArrayOf('a', 'b'), "wrong-captured"), 'b')}")
    println("direct-nonlocal=${directNonLocal(IndexedSequence(charArrayOf('a', 'b'), "wrong-direct-nonlocal"))}")
    println("safe-nonlocal=${safeNonLocal(IndexedSequence(charArrayOf('a', 'b'), "wrong-safe-nonlocal"))}")
    println("safe-nonlocal-null=${safeNonLocal(null)}")
    println("captured-nonlocal=${capturedNonLocal(IndexedSequence(charArrayOf('a', 'b'), "wrong-captured-nonlocal"), '!')}")
    println("nullable-nonlocal=${nullableNonLocal(IndexedSequence(charArrayOf('a', 'b'), "wrong-nullable-nonlocal"), '!')}")
    println("nullable-nonlocal-null=${nullableNonLocal(null, '!')}")
    println("discarded-nonlocal=${discardedNonLocal(IndexedSequence(charArrayOf('a', 'b'), "wrong-discarded"))}")

    println("nullable-null=${nullableSingleOrNull(null) == null}")
    println("nullable-one=${nullableSingleOrNull(IndexedSequence(charArrayOf('N'), "wrong-nullable-one"))}")
    println("nullable-predicate-null=${nullableSingleOrNullPredicate(null, 'b') == null}")
    println("nullable-predicate-nonnull=${nullableSingleOrNullPredicate(IndexedSequence(charArrayOf('a', 'b'), "wrong-nullable-predicate"), 'b')}")

    val builder: CharSequence = StringBuilder("Q")
    println("builder=${builder.single()}")
    val string: CharSequence = "R"
    println("string=${string.singleOrNull()}")

    val utf16: CharSequence = IndexedSequence(charArrayOf('\uD83D', '\uDE00'), "wrong-utf16")
    println("utf16-length=${utf16.length}")
    println("utf16-single-or-null=${utf16.singleOrNull() == null}")
}
