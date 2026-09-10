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

    override fun toString(): String = "different display"
}

private fun capturedLast(source: CharSequence): Char {
    val expected = 'b'
    return source.last { it == expected }
}

private fun nonLocalLast(source: CharSequence): Char {
    return source.last {
        if (it == 'x') return '!'
        false
    }
}

private fun nonLocalLastOrNull(source: CharSequence): Char {
    source.lastOrNull {
        if (it == 'x') return '!'
        false
    }
    return '?'
}

private fun capturedNonLocalLast(source: CharSequence, captured: Char): Char {
    source.last {
        return captured
    }
    return '?'
}

private fun nullableCapturedLast(source: CharSequence?, captured: Char): Char {
    return source?.lastOrNull {
        return captured
    } ?: '?'
}

fun main() {
    val source: CharSequence = "a\uD83D\uDE00ba"
    println(source.last().code)
    println(source.lastOrNull()?.code ?: -1)
    println(source.last { it == 'a' }.code)
    println(source.lastOrNull { it == '\uD83D' }?.code ?: -1)
    println(source.lastIndex)

    val builder: CharSequence = StringBuilder("xy")
    println(builder.last().code)
    println(builder.lastOrNull()?.code ?: -1)
    println(builder.lastIndex)

    val empty: CharSequence = ""
    try {
        empty.last()
    } catch (error: NoSuchElementException) {
        println(error.message)
    }
    println(empty.lastOrNull()?.code ?: -1)

    try {
        source.last { it == 'z' }
    } catch (error: NoSuchElementException) {
        println(error.message)
    }
    var predicateCalls = 0
    println(source.lastOrNull { predicateCalls++; false } ?: -1)
    println(predicateCalls)

    val visited = StringBuilder()
    println(source.last { value ->
        visited.append(value)
        value == 'b'
    }.code)
    println(visited.toString())

    println(capturedLast(source).code)
    println(nonLocalLast("ax").code)
    println(nonLocalLastOrNull("xa").code)
    println(nonLocalLastOrNull("ab").code)
    println(capturedNonLocalLast("ax", '!').code)
    println(nullableCapturedLast("ax", '!').code)
    println(nullableCapturedLast(null, '!').code)

    val utf16: CharSequence = TrackingCharSequence("A\uD83D\uDE00B")
    println(utf16.last().code)
    println(utf16.lastOrNull { it == '\uDE00' }?.code ?: -1)
    val tracked = utf16 as TrackingCharSequence
    println(tracked.lengthReads > 0)
    println(tracked.characterReads > 0)
    println(utf16.lastIndex)
}
