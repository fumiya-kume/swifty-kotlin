class CustomSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.subSequence(startIndex, endIndex)
}

private fun report(label: String, value: Any) {
    println("$label=$value")
}

private fun reportAll(label: String, source: CharSequence) {
    report("$label-double", source.sumOf { it.code.toDouble() })
    report("$label-int", source.sumOf { it.code })
    report("$label-long", source.sumOf { it.code.toLong() })
    report("$label-uint", source.sumOf { it.code.toUInt() })
    report("$label-ulong", source.sumOf { it.code.toULong() })
}

fun main() {
    reportAll("string", "A😀")
    reportAll("interface", ("A😀" as CharSequence))
    reportAll("builder", StringBuilder("A😀"))
    reportAll("custom", CustomSequence("A😀"))
    reportAll("empty", "")
}
