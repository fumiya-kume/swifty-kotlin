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

    val trackedZero = TrackingCharSequence("A\uD83D\uDE00B")
    println("tracked-zero='${trackedZero.repeat(0)}':length=${trackedZero.lengthReads}:chars=${trackedZero.characterReads}")

    val trackedOne = TrackingCharSequence("A\uD83D\uDE00B")
    println("tracked-one='${trackedOne.repeat(1)}':length=${trackedOne.lengthReads}:chars=${trackedOne.characterReads}")

    val trackedTwo = TrackingCharSequence("A\uD83D\uDE00B")
    val trackedSequence: CharSequence = trackedTwo
    println("tracked-two='${trackedSequence.repeat(n = 2)}':length=${trackedTwo.lengthReads}:chars=${trackedTwo.characterReads}")

    println("utf16='${"a\uD83D\uDE00".repeat(2)}'")
    println("string='${"z".repeat(2)}'")
}
