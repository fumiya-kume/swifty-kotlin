private class DisplayOnlyCharSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.subSequence(startIndex, endIndex)

    override fun toString(): String = "display-only"
}

private class CountingCharSequence(private val content: String) : CharSequence {
    var lengthReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return content.length
        }

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.subSequence(startIndex, endIndex)

    override fun toString(): String = "counted-display"
}

fun main() {
    println("".none())
    println("abc".none())
    println("😀".none())

    val emptyString: CharSequence = ""
    val nonEmptyString: CharSequence = "abc"
    println(emptyString.none())
    println(nonEmptyString.none())

    val emptyBuilder: CharSequence = StringBuilder()
    val nonEmptyBuilder: CharSequence = StringBuilder("😀")
    println(emptyBuilder.none())
    println(nonEmptyBuilder.none())

    val emptyCustom: CharSequence = DisplayOnlyCharSequence("")
    val nonEmptyCustom: CharSequence = DisplayOnlyCharSequence("😀")
    println(emptyCustom.none())
    println(nonEmptyCustom.none())

    val counted = CountingCharSequence("")
    println(counted.none())
    println(counted.lengthReads)

    println("abc".none { it == 'z' })
    println("abc".none { it == 'b' })
}
