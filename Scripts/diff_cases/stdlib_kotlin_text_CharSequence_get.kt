private class RecordedSequence : CharSequence {
    var lengthReads = 0
    var characterReads = 0

    override val length: Int
        get() { lengthReads++; return 3 }

    override fun get(index: Int): Char {
        characterReads++
        return when (index) {
            0 -> 'a'
            1 -> '\uD83D'
            2 -> '\uDE00'
            else -> throw IndexOutOfBoundsException("unexpected index")
        }
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        throw UnsupportedOperationException("unused")

    override fun toString(): String = "unrelated display"
}

private fun namedReturn(source: CharSequence, value: Char): Char {
    source.getOrElse(defaultValue = { return value }, index = -1)
    return '?'
}

private fun safeReturn(source: CharSequence?, value: Char): Char {
    source?.getOrElse(defaultValue = { return value }, index = -1)
    return '?'
}

fun main() {
    val text: CharSequence = "a\uD83D\uDE00"
    println(text.getOrNull(0)?.code)
    println(text.getOrNull(1)?.code)
    println(text.getOrNull(2)?.code)
    println(text.getOrNull(3))
    println(text.getOrNull(Int.MIN_VALUE))
    println(text.getOrNull(Int.MAX_VALUE))
    val empty: CharSequence = ""
    println(empty.getOrNull(0))
    val builder: CharSequence = StringBuilder("abc")
    println(builder.getOrElse(1) { '?' })

    val recorded = RecordedSequence()
    val source: CharSequence = recorded
    println(source.getOrNull(-1))
    println(recorded.lengthReads)
    println(source.getOrNull(1)?.code)
    println(recorded.characterReads)
    println(recorded.lengthReads)
    println(source.getOrNull(3))
    println(recorded.characterReads)
    println(recorded.lengthReads)

    recorded.lengthReads = 0
    var defaults = 0
    println(source.getOrElse(2) { defaults++; '?' }.code)
    println(defaults)
    println(source.getOrElse(-4) { defaults++; if (it == -4) '-' else '?' })
    println(defaults)
    println(recorded.lengthReads)
    println(source.getOrElse(Int.MAX_VALUE) { if (it == Int.MAX_VALUE) '+' else '?' })
    println(recorded.characterReads)
    println(recorded.lengthReads)
    println(namedReturn(source, 'n'))
    println(safeReturn(source, 's'))
    println(safeReturn(null, 's'))
    try {
        source.getOrElse(5) { throw IllegalStateException("fallback") }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
