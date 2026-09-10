private class RecordingCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        println("member:$startIndex:$endIndex")
        return value.substring(startIndex, endIndex)
    }

    override fun toString(): String = "wrong-toString"
}

private class CountingCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() {
            println("length-read")
            return value.length
        }

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        println("counting-member:$startIndex:$endIndex")
        return value.substring(startIndex, endIndex)
    }

    override fun toString(): String = "counting-wrong-toString"
}

private class MemberRangeCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)

    fun subSequence(range: IntRange): CharSequence {
        println("member-range-subSequence")
        return value.substring(range.start, range.endInclusive + 1)
    }

    fun substring(range: IntRange): String {
        println("member-range-substring")
        return value.substring(range.start, range.endInclusive + 1)
    }
}

private fun MemberRangeCharSequence.subSequence(range: IntRange): CharSequence {
    println("extension-range-subSequence")
    return "extension"
}

private fun MemberRangeCharSequence.substring(range: IntRange): String {
    println("extension-range-substring")
    return "extension"
}

fun main() {
    val custom: CharSequence = RecordingCharSequence("abcd")
    println("custom1=" + custom.substring(1))
    println("custom2=" + custom.substring(1, 3))
    println("customRange=" + custom.substring(1..3))
    println("customNamed=" + custom.substring(startIndex = 1, endIndex = 3))
    println("customRangeNamed=" + custom.substring(range = 1..3))

    val counting: CharSequence = CountingCharSequence("abcd")
    println("counting=" + counting.substring(1))

    val concrete = RecordingCharSequence("abcd")
    println("concrete-range=" + concrete.substring(1..3))

    val memberRange = MemberRangeCharSequence("abcd")
    println("member-subSequence-range=" + memberRange.subSequence(1..3))
    println("member-substring-range=" + memberRange.substring(1..3))

    val text: String = "abcd"
    println("string1=" + text.substring(1))
    println("string2=" + text.substring(1, 3))
    println("stringRange=" + text.substring(1..3))

    val builder = StringBuilder("abcd")
    val sequence: CharSequence = builder
    println("builder=" + sequence.substring(1, 3))
    println("builder-range=" + builder.substring(1..3))

    val astral: CharSequence = "A😀B"
    println("utf16-length=" + astral.substring(1, 3).length)
    println("utf16-range=" + astral.substring(1..2))
    println("empty-end=" + text.substring(4..3).length)

    try {
        text.substring(-1)
        println("negative=NO_ERROR")
    } catch (_: IndexOutOfBoundsException) {
        println("negative=INDEX")
    }
    try {
        text.substring(5)
        println("past-end=NO_ERROR")
    } catch (_: IndexOutOfBoundsException) {
        println("past-end=INDEX")
    }
    try {
        text.substring(3, 1)
        println("reversed=NO_ERROR")
    } catch (_: IndexOutOfBoundsException) {
        println("reversed=INDEX")
    }
    try {
        text.substring(0..Int.MAX_VALUE)
        println("range-overflow=NO_ERROR")
    } catch (_: IndexOutOfBoundsException) {
        println("range-overflow=INDEX")
    }
}
