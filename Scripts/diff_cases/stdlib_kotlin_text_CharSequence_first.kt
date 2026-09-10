private class TrackingCharSequence(initial: String) : CharSequence {
    private var content = initial
    var lengthReads = 0
    var getReads = 0

    override val length: Int
        get() {
            lengthReads += 1
            return content.length
        }

    override fun get(index: Int): Char {
        getReads += 1
        return content[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)

    override fun toString(): String = "different display"

    fun append(value: Char) {
        content = content + value
    }
}

private fun capturedPredicate(sequence: CharSequence): Char {
    val expected = 'b'
    return sequence.first { it == expected }
}

fun main() {
    println("abc".first().code)
    println("abc".firstOrNull()?.code ?: -1)
    println(StringBuilder("xyz").first().code)

    try {
        "".first()
    } catch (error: NoSuchElementException) {
        println(error.message)
    }
    println("".firstOrNull() ?: -1)

    try {
        "abc".first { it == 'z' }
    } catch (error: NoSuchElementException) {
        println(error.message)
    }
    println("abc".firstOrNull { it == 'z' } ?: -1)

    val order = StringBuilder()
    val ordered = "abc".first { value ->
        order.append(value)
        value == 'b'
    }
    println(ordered.code)
    println(order.toString())

    println(capturedPredicate("abc").code)

    val utf16: CharSequence = TrackingCharSequence("A\uD83D\uDE00B")
    println(utf16.first().code)
    println(utf16.firstOrNull { it == '\uDE00' }?.code ?: -1)

    val growing = TrackingCharSequence("a")
    val dynamic = growing.firstOrNull { value ->
        if (value == 'a') {
            growing.append('b')
            false
        } else {
            value == 'b'
        }
    }
    println(dynamic?.code ?: -1)
    println(growing.lengthReads > 1)
    println(growing.getReads > 1)
}
