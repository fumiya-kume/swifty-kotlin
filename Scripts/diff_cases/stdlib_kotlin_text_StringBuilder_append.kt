private class DisplayValue {
    override fun toString(): String = "display"
}

private class IndexedValue : CharSequence {
    override val length: Int get() = 2
    override fun get(index: Int): Char = if (index == 0) 'o' else 'k'
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        "ok".subSequence(startIndex, endIndex)
    override fun toString(): String = "different"
}

private fun checkRange(offset: Int, count: Int) {
    val builder = StringBuilder("prefix")
    try {
        builder.append(charArrayOf('a', 'b'), offset, count)
        println("accepted:${builder}")
    } catch (error: IndexOutOfBoundsException) {
        println("invalid:${builder}")
    }
}

fun main() {
    val builder = StringBuilder()
    println(builder.appendLine(true) === builder)
    builder.appendLine((-128).toByte())
    builder.appendLine('Q')
    builder.appendLine(charArrayOf('a', '\uD83E', '\uDD66'))
    val sequence: CharSequence = IndexedValue()
    builder.appendLine(sequence)
    builder.appendLine(1.25)
    builder.appendLine(2.5f)
    builder.appendLine(Int.MIN_VALUE)
    builder.appendLine(Long.MIN_VALUE)
    builder.appendLine((-32768).toShort())
    val text: String? = "text"
    builder.appendLine(text)
    val absentText: String? = null
    val absentSequence: CharSequence? = null
    builder.appendLine(absentText)
    builder.appendLine(absentSequence)
    val display: Any? = DisplayValue()
    builder.appendLine(display)
    print(builder.toString())

    val existing = StringBuilder()
    println(existing.append(display) === existing)
    existing.append((-128).toByte()).append((-32768).toShort())
    println(existing)
    val chars = charArrayOf('a', '\uD83E', '\uDD66', 'z')
    val part = StringBuilder()
    println(part.append(chars, 1, 2) === part)
    println(part)
    part.clear()
    println(part.appendRange(chars, 1, 3) === part)
    println(part)
    checkRange(0, 0)
    checkRange(2, 0)
    checkRange(0, 2)
    checkRange(-1, 1)
    checkRange(0, -1)
    checkRange(2, 1)
    checkRange(Int.MAX_VALUE, 1)
    checkRange(1, Int.MAX_VALUE)
}
