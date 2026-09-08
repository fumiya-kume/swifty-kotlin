private class TrackingCharSequence(initial: String) : CharSequence {
    private val content = initial
    var lengthReads = 0
    var characterReads = 0

    override val length: Int
        get() {
            lengthReads++
            return content.length
        }

    override fun get(index: Int): Char {
        characterReads++
        return content[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)

    override fun toString(): String = "custom-display"
}

private fun reverse(source: CharSequence): String = source.reversed().toString()

fun main() {
    val empty: CharSequence = ""
    println("empty='${reverse(empty)}'")

    val single: CharSequence = "x"
    println("single='${reverse(single)}'")

    val source: CharSequence = "ab\uD83D\uDE00cd"
    println("source='${reverse(source)}'")

    val builder: CharSequence = StringBuilder("xy\uD83D\uDE00")
    println("builder='${reverse(builder)}'")

    val highLow: CharSequence = "\uD800\uDC00"
    println("high-low='${reverse(highLow)}'")

    val tracked = TrackingCharSequence("A\uD83D\uDE00B")
    val trackedSequence: CharSequence = tracked
    println("tracked='${reverse(trackedSequence)}':length=${tracked.lengthReads > 0}:chars=${tracked.characterReads > 0}")

    println("string='${"abc".reversed()}'")
}
