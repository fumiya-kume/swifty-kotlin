private class TrackingCharSequence(initial: String) : CharSequence {
    private var content = initial
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

private fun negativeRepeat(source: CharSequence, count: Int): String {
    return try {
        source.repeat(count)
    } catch (error: IllegalArgumentException) {
        error.message ?: "missing"
    }
}

fun main() {
    val source: CharSequence = "ab"
    println("zero='${source.repeat(0)}'")
    println("one='${source.repeat(1)}'")
    println("two='${source.repeat(2)}'")
    println("three='${source.repeat(3)}'")
    println("negative='${negativeRepeat(source, -1)}'")
    println("minimum='${negativeRepeat(source, Int.MIN_VALUE)}'")

    val builder: CharSequence = StringBuilder("xy")
    println("builder-two='${builder.repeat(2)}'")
    println("builder-one='${builder.repeat(1)}'")

    val empty: CharSequence = ""
    println("empty-zero='${empty.repeat(0)}'")
    println("empty-max-length=${empty.repeat(Int.MAX_VALUE).length}")

    val tracked = TrackingCharSequence("A\uD83D\uDE00B")
    val trackedSequence: CharSequence = tracked
    println("tracked-one='${trackedSequence.repeat(1)}'")
    println("tracked-two='${trackedSequence.repeat(2)}'")
    println("tracked-reads=${tracked.lengthReads > 0}:${tracked.characterReads > 0}")

    println("utf16='${"a\uD83D\uDE00".repeat(2)}'")
    println("string='${"z".repeat(2)}'")
}
