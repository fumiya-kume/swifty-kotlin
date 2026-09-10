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

private class StatefulCharSequence(private val size: Int) : CharSequence {
    var lengthReads = 0
    var characterReads = 0
    var indices = ""

    override val length: Int
        get() {
            lengthReads++
            return size
        }

    override fun get(index: Int): Char {
        if (indices.isNotEmpty()) indices += ","
        indices += index.toString()
        val value = ('a'.code + characterReads).toChar()
        characterReads++
        return value
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        "".substring(startIndex, endIndex)

    override fun toString(): String = "stateful-display"
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

    val stateful = StatefulCharSequence(4)
    println("stateful='${reverse(stateful)}':length=${stateful.lengthReads}:gets=${stateful.indices}")

    println("string='${"abc".reversed()}'")
}
