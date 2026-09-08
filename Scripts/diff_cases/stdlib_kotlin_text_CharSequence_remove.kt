private class RecordedSequence(private val content: String) : CharSequence {
    var subSequenceCalls: Int = 0
    var lengthCalls: Int = 0
    var getCalls: Int = 0

    override val length: Int
        get() {
            lengthCalls += 1
            return content.length
        }

    override fun get(index: Int): Char {
        getCalls += 1
        return content[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        subSequenceCalls += 1
        if (startIndex == 0 && endIndex == length) {
            return RecordedSlice(content)
        }
        return content.substring(startIndex, endIndex)
    }

    override fun toString(): String = "wrong-toString"
}

private class RecordedSlice(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)

    override fun toString(): String = "subSequence($content)"
}

fun main() {
    val string: CharSequence = "A😀BC"
    println(string.removeRange(1, 3))
    println(string.removeRange(1..2))

    val builder: CharSequence = StringBuilder("A😀BC")
    println(builder.removeRange(1, 3))

    val custom = RecordedSequence("A😀BC")
    println(custom.removeRange(1, 3))
    println(custom.subSequenceCalls)
    println(custom.lengthCalls)
    println(custom.getCalls)

    val empty = RecordedSequence("abc")
    println(empty.removeRange(1, 1).toString())
    println(empty.subSequenceCalls)
    println(empty.lengthCalls)

    println("abc".removeRange(1..1))
    println("abc".removeRange(0, 3))

    val bounded: CharSequence = RecordedSequence("abc")
    fun attempt(label: String, action: () -> CharSequence) {
        try {
            println("$label:ok:${action()}")
        } catch (e: NegativeArraySizeException) {
            println("$label:negative:${e.message}")
        } catch (e: IndexOutOfBoundsException) {
            println("$label:index:${e.message}")
        }
    }

    attempt("negative", { bounded.removeRange(-1, 0) })
    attempt("end", { bounded.removeRange(0, 4) })
    attempt("max", { bounded.removeRange(Int.MAX_VALUE, Int.MAX_VALUE) })
    attempt("reversed", { bounded.removeRange(2, 1) })
    attempt("range-max", { bounded.removeRange(Int.MAX_VALUE..Int.MAX_VALUE) })
    attempt("range-negative", { bounded.removeRange(-1..-1) })
    attempt("empty", { bounded.removeRange(1, 1) })
}
