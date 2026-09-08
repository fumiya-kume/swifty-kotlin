private class TrackedSequence : CharSequence {
    var reads: Int = 0
    var lengthReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return 3
        }

    override fun get(index: Int): Char {
        reads++
        return when (index) {
            0 -> 'a'
            1 -> '\uD83D'
            2 -> '\uDE00'
            else -> throw IndexOutOfBoundsException("index")
        }
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        throw UnsupportedOperationException("unused")

    override fun toString(): String = "unrelated"
}

private fun codeAt(source: CharSequence, index: Int): Int = source.elementAt(index).code

private fun nonLocalDefault(source: CharSequence): Char {
    source.elementAtOrElse(-1) { return 'z' }
    return '?'
}

private fun nonLocalSafeDefault(source: CharSequence?): Char {
    source?.elementAtOrElse(-1) { return 's' }
    return '?'
}

private fun capturedDefault(source: CharSequence, value: Char): Char {
    source.elementAtOrElse(-1) { return value }
    return '?'
}

fun main() {
    val text: CharSequence = "a\uD83D\uDE00"
    println(codeAt(text, 0))
    println(codeAt(text, 1))
    println(codeAt(text, 2))
    println(codeAt(StringBuilder("xyz"), 1))
    println(text.elementAtOrNull(3))
    println(text.elementAtOrNull(Int.MAX_VALUE))
    println(text.elementAtOrNull(Int.MIN_VALUE))
    val empty: CharSequence = ""
    println(empty.elementAtOrNull(0))

    val tracked = TrackedSequence()
    val source: CharSequence = tracked
    println(codeAt(source, 1))
    println(tracked.reads)
    println(tracked.lengthReads)
    var defaults = 0
    println(source.elementAtOrElse(2) { defaults++; '?' }.code)
    println(defaults)
    println(source.elementAtOrElse(-4) { defaults++; if (it == -4) '-' else '?' })
    println(defaults)
    println(tracked.reads)
    println(tracked.lengthReads)
    println(nonLocalDefault(source))
    println(nonLocalSafeDefault(source))
    println(nonLocalSafeDefault(null))
    println(capturedDefault(source, 'c'))

    try {
        source.elementAt(3)
    } catch (error: IndexOutOfBoundsException) {
        println(error.message)
    }
    try {
        source.elementAtOrElse(10) { throw IllegalStateException("fallback") }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
