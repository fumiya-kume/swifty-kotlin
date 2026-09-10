private class RecordingCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() {
            println("length")
            return value.length
        }

    override fun get(index: Int): Char {
        println("get:$index")
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        println("subSequence:$startIndex:$endIndex")
        return value.substring(startIndex, endIndex)
    }

    override fun toString(): String {
        println("toString")
        return "wrong-toString"
    }
}

private class CodeUnitSequence(
    private val units: CharArray,
    private val offset: Int,
    private val count: Int
) : CharSequence {
    constructor(units: CharArray) : this(units, 0, units.size)

    override val length: Int
        get() = count

    override fun get(index: Int): Char = units[offset + index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        CodeUnitSequence(units, offset + startIndex, endIndex - startIndex)

    override fun toString(): String = "wrong-code-units"
}

private fun charCodes(value: CharSequence): String {
    var result = ""
    var index = 0
    while (index < value.length) {
        if (index > 0) result += ","
        result += value[index].code.toString()
        index++
    }
    return result
}

fun main() {
    val custom: CharSequence = RecordingCharSequence("abcd")
    println("range=${custom.slice(1..2)}")
    println("range-empty=${custom.slice(2 until 2)}")
    println("range-reversed=${custom.slice(3..1)}")
    println("iter=${custom.slice(listOf(3, 1, 3))}")
    val emptyIndices: Iterable<Int> = emptyList<Int>()
    println("iter-empty=${custom.slice(emptyIndices)}")

    val builder: CharSequence = StringBuilder("abcd")
    println("builder-range=${builder.slice(0..1)}")
    println("builder-iter=${builder.slice(listOf(3, 0))}")
    val stringAsSequence: CharSequence = "abcd"
    println("string-range=${stringAsSequence.slice(1..2)}")
    println("string-iter=${stringAsSequence.slice(listOf(2, 0, 2))}")

    try {
        custom.slice(listOf(-1))
        println("negative-missed")
    } catch (e: IndexOutOfBoundsException) {
        println("negative=IndexOutOfBoundsException")
    }
    try {
        custom.slice(listOf(4))
        println("end-missed")
    } catch (e: IndexOutOfBoundsException) {
        println("end=IndexOutOfBoundsException")
    }
    try {
        custom.slice(Int.MAX_VALUE..Int.MAX_VALUE)
        println("overflow-missed")
    } catch (e: IndexOutOfBoundsException) {
        println("overflow=IndexOutOfBoundsException")
    }

    val utf16: CharSequence = CodeUnitSequence(charArrayOf('A', '\uD83D', '\uDF66', 'B'))
    val rangeUtf16 = utf16.slice(1..2)
    val iterableUtf16 = utf16.slice(listOf(1, 2))
    println("utf16-range=${charCodes(rangeUtf16)}")
    println("utf16-iter=${charCodes(iterableUtf16)}")
}
