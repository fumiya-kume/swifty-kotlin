private class TrackedText(private val chars: CharArray) : CharSequence {
    var trace: String = ""
    override val length: Int
        get() {
            trace += "L;"
            return chars.size
        }
    override fun get(index: Int): Char {
        trace += "G$index;"
        return chars[index]
    }
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        trace += "S$startIndex:$endIndex;"
        return StringBuilder().appendRange(chars, startIndex, endIndex).toString()
    }
    override fun toString(): String = "wrong-rendering"
}

private fun inspect(chars: CharArray, mode: Int) {
    val source = TrackedText(chars)
    var calls = ""
    val result: CharSequence = when (mode) {
        0 -> source.trim { calls += "${it.code},"; it == '_' }
        1 -> source.trimStart { calls += "${it.code},"; it == '_' }
        else -> source.trimEnd { calls += "${it.code},"; it == '_' }
    }
    println("$mode:$result:$calls:${source.trace}")
}

private fun directNonLocal(source: CharSequence): String {
    source.trim { return "!" }
    return "?"
}

private fun capturedNonLocal(source: CharSequence, captured: String): String {
    source.trimEnd(predicate = { return captured })
    return "?"
}

private fun nullableNonLocal(source: CharSequence?, captured: String): String {
    source?.trimStart { return captured }
    return "?"
}

fun main() {
    for (mode in 0..2) {
        inspect(charArrayOf('_', 'x', '_'), mode)
        inspect(charArrayOf('_', '_'), mode)
        inspect(charArrayOf(), mode)
        inspect(charArrayOf('x'), mode)
    }
    val text: CharSequence = "\t\u00A0 hello\u2003\r\n"
    println("[${text.trim()}]")
    println(text.trimStart().toString().endsWith("\r\n"))
    println(text.trimEnd().toString().startsWith("\t\u00A0"))
    val underscores: CharSequence = "_x_"
    println(underscores.trim('_'))
    println(underscores.trimStart('_'))
    println(underscores.trimEnd('_'))
    println(underscores.trim(*charArrayOf()))
    println(underscores.trimStart(*charArrayOf('_', 'x')))
    println(underscores.trimEnd(*charArrayOf('_', 'x')))
    val builder: CharSequence = StringBuilder("_\uD83D\uDE00_")
    val trimmed = builder.trim('_')
    println("${trimmed.length}:${trimmed[0].code}:${trimmed[1].code}")
    println(directNonLocal("x"))
    println(capturedNonLocal("x", "captured"))
    println(nullableNonLocal("x", "nullable"))
    println(nullableNonLocal(null, "unused"))
    println(directNonLocal(""))
    var calls = 0
    try {
        underscores.trim { calls += 1; throw IllegalStateException("predicate") }
    } catch (error: IllegalStateException) {
        println("${error.message}:$calls")
    }
    val string: String = " x ".trim()
    println(string)
}
