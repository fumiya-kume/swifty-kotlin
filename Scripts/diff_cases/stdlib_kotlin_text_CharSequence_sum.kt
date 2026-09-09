class CustomSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.subSequence(startIndex, endIndex)
}

private class RecordingSequence(initial: String) : CharSequence {
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
        content.subSequence(startIndex, endIndex)

    fun append(value: Char) {
        content += value
    }

    fun truncate(newLength: Int) {
        content = content.substring(0, newLength)
    }

    override fun toString(): String = content
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

private fun growDouble(): String {
    val source = RecordingSequence("A")
    var first = true
    val value = source.sumOf { ch ->
        if (first) {
            first = false
            source.append('B')
        }
        ch.code.toDouble()
    }
    return "$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun growInt(): String {
    val source = RecordingSequence("A")
    var first = true
    val value = source.sumOf { ch ->
        if (first) {
            first = false
            source.append('B')
        }
        ch.code
    }
    return "$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun growLong(): String {
    val source = RecordingSequence("A")
    var first = true
    val value = source.sumOf { ch ->
        if (first) {
            first = false
            source.append('B')
        }
        ch.code.toLong()
    }
    return "$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun growUInt(): String {
    val source = RecordingSequence("A")
    var first = true
    val value = source.sumOf { ch ->
        if (first) {
            first = false
            source.append('B')
        }
        ch.code.toUInt()
    }
    return "$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun growULong(): String {
    val source = RecordingSequence("A")
    var first = true
    val value = source.sumOf { ch ->
        if (first) {
            first = false
            source.append('B')
        }
        ch.code.toULong()
    }
    return "$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun shrinkInt(): String {
    val source = RecordingSequence("AB")
    var first = true
    var threw = false
    var value = 0
    try {
        value = source.sumOf { ch ->
            if (first) {
                first = false
                source.truncate(1)
            }
            ch.code
        }
    } catch (_: Throwable) {
        threw = true
    }
    return "$threw/$value/$source/${source.lengthReads}/${source.getReads}"
}

private fun doubleDirect(): String {
    val ignored: Double = "ab".sumOf { if (it == '\u0000') 0.0 else return "double-direct!" }
    return "double-tail:$ignored"
}

private fun doubleCaptured(): String {
    val marker = "double"
    val ignored: Double = "ab".sumOf { if (marker.length > 0) return "$marker-captured!" else 0.0 }
    return "double-tail:$ignored"
}

private fun doubleNullable(): String {
    val source: CharSequence? = "ab"
    val ignored: Double? = source?.sumOf { if (it == '\u0000') 0.0 else return "double-nullable!" }
    return "double-tail:$ignored"
}

private fun doubleDiscarded(): String {
    "ab".sumOf { if (it == '\u0000') 0.0 else return "double-discarded!" }
    return "double-tail?"
}

private fun intDirect(): String {
    val ignored: Int = "ab".sumOf { if (it == '\u0000') 0 else return "int-direct!" }
    return "int-tail:$ignored"
}

private fun intCaptured(): String {
    val marker = "int"
    val ignored: Int = "ab".sumOf { if (marker.length > 0) return "$marker-captured!" else 0 }
    return "int-tail:$ignored"
}

private fun intNullable(): String {
    val source: CharSequence? = "ab"
    val ignored: Int? = source?.sumOf { if (it == '\u0000') 0 else return "int-nullable!" }
    return "int-tail:$ignored"
}

private fun intDiscarded(): String {
    "ab".sumOf { if (it == '\u0000') 0 else return "int-discarded!" }
    return "int-tail?"
}

private fun longDirect(): String {
    val ignored: Long = "ab".sumOf { if (it == '\u0000') 0L else return "long-direct!" }
    return "long-tail:$ignored"
}

private fun longCaptured(): String {
    val marker = "long"
    val ignored: Long = "ab".sumOf { if (marker.length > 0) return "$marker-captured!" else 0L }
    return "long-tail:$ignored"
}

private fun longNullable(): String {
    val source: CharSequence? = "ab"
    val ignored: Long? = source?.sumOf { if (it == '\u0000') 0L else return "long-nullable!" }
    return "long-tail:$ignored"
}

private fun longDiscarded(): String {
    "ab".sumOf { if (it == '\u0000') 0L else return "long-discarded!" }
    return "long-tail?"
}

private fun uintDirect(): String {
    val ignored: UInt = "ab".sumOf { if (it == '\u0000') 0u else return "uint-direct!" }
    return "uint-tail:$ignored"
}

private fun uintCaptured(): String {
    val marker = "uint"
    val ignored: UInt = "ab".sumOf { if (marker.length > 0) return "$marker-captured!" else 0u }
    return "uint-tail:$ignored"
}

private fun uintNullable(): String {
    val source: CharSequence? = "ab"
    val ignored: UInt? = source?.sumOf { if (it == '\u0000') 0u else return "uint-nullable!" }
    return "uint-tail:$ignored"
}

private fun uintDiscarded(): String {
    "ab".sumOf { if (it == '\u0000') 0u else return "uint-discarded!" }
    return "uint-tail?"
}

private fun ulongDirect(): String {
    val ignored: ULong = "ab".sumOf { if (it == '\u0000') 0uL else return "ulong-direct!" }
    return "ulong-tail:$ignored"
}

private fun ulongCaptured(): String {
    val marker = "ulong"
    val ignored: ULong = "ab".sumOf { if (marker.length > 0) return "$marker-captured!" else 0uL }
    return "ulong-tail:$ignored"
}

private fun ulongNullable(): String {
    val source: CharSequence? = "ab"
    val ignored: ULong? = source?.sumOf { if (it == '\u0000') 0uL else return "ulong-nullable!" }
    return "ulong-tail:$ignored"
}

private fun ulongDiscarded(): String {
    "ab".sumOf { if (it == '\u0000') 0uL else return "ulong-discarded!" }
    return "ulong-tail?"
}

private fun intOverflow(): Int = "ab".sumOf { Int.MAX_VALUE }
private fun longOverflow(): Long = "ab".sumOf { Long.MAX_VALUE }
private fun uintOverflow(): UInt = "ab".sumOf { UInt.MAX_VALUE }
private fun ulongOverflow(): ULong = "ab".sumOf { ULong.MAX_VALUE }

fun main() {
    reportAll("string", "A😀")
    reportAll("interface", ("A😀" as CharSequence))
    reportAll("builder", StringBuilder("A😀"))
    reportAll("custom", CustomSequence("A😀"))
    reportAll("empty", "")

    report("grow-double", growDouble())
    report("grow-int", growInt())
    report("grow-long", growLong())
    report("grow-uint", growUInt())
    report("grow-ulong", growULong())
    report("shrink-int", shrinkInt())

    report("int-overflow", intOverflow())
    report("long-overflow", longOverflow())
    report("uint-overflow", uintOverflow())
    report("ulong-overflow", ulongOverflow())

    report("double-direct", doubleDirect())
    report("double-captured", doubleCaptured())
    report("double-nullable", doubleNullable())
    report("double-discarded", doubleDiscarded())
    report("int-direct", intDirect())
    report("int-captured", intCaptured())
    report("int-nullable", intNullable())
    report("int-discarded", intDiscarded())
    report("long-direct", longDirect())
    report("long-captured", longCaptured())
    report("long-nullable", longNullable())
    report("long-discarded", longDiscarded())
    report("uint-direct", uintDirect())
    report("uint-captured", uintCaptured())
    report("uint-nullable", uintNullable())
    report("uint-discarded", uintDiscarded())
    report("ulong-direct", ulongDirect())
    report("ulong-captured", ulongCaptured())
    report("ulong-nullable", ulongNullable())
    report("ulong-discarded", ulongDiscarded())
}
