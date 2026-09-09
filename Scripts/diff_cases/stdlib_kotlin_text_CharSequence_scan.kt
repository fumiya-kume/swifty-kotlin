private class CountingSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0
    var getReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override fun get(index: Int): Char {
        getReads++
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private class MutableSequence(private val value: String) : CharSequence {
    var visibleLength: Int = value.length

    override val length: Int
        get() = visibleLength

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private fun renderInts(values: List<Int>): String {
    val result = StringBuilder()
    var index = 0
    while (index < values.size) {
        if (index > 0) result.append('|')
        result.append(values[index])
        index++
    }
    return result.toString()
}

private fun renderStrings(values: List<String>): String {
    val result = StringBuilder()
    var index = 0
    while (index < values.size) {
        if (index > 0) result.append('|')
        result.append(values[index])
        index++
    }
    return result.toString()
}

private fun renderNullableStrings(values: List<String?>): String {
    val result = StringBuilder()
    var index = 0
    while (index < values.size) {
        if (index > 0) result.append('|')
        result.append(values[index])
        index++
    }
    return result.toString()
}

private fun directScanReturn(source: CharSequence, target: Char): Int {
    source.scan(0) { accumulator, value ->
        if (value == target) return 61
        accumulator + 1
    }
    return -1
}

private fun safeScanReturn(source: CharSequence?, target: Char): Int {
    source?.scan(0) { accumulator, value ->
        if (value == target) return 62
        accumulator + 1
    }
    return -1
}

private fun capturedScanReturn(source: CharSequence, target: Char): Int {
    val expected = target
    source.scan(0, operation = { accumulator, value ->
        if (value == expected) return 63
        accumulator + 1
    })
    return -1
}

private fun namedIndexedScanReturn(source: CharSequence, target: Char): Int {
    source.scanIndexed(0, operation = { index, accumulator, value ->
        if (value == target) return 64
        accumulator + index + 1
    })
    return -1
}

private fun throwingScan(source: CharSequence): String {
    return try {
        source.scan(0) { accumulator, value ->
            if (value == 'b') throw IllegalStateException("stop-scan")
            accumulator + value.code
        }
        "completed"
    } catch (error: IllegalStateException) {
        error.message ?: "null"
    }
}

fun main() {
    val intScan = "abc".scan(0) { accumulator, value -> accumulator + value.code }
    println(renderInts(intScan))

    val indexedScan = "abc".scanIndexed("") { index, accumulator, value ->
        accumulator + index + value
    }
    println(renderStrings(indexedScan))

    val nullableScan = "ab".scan<String?>(null) { accumulator, value ->
        if (accumulator == null) value.toString() else accumulator + value
    }
    println(renderNullableStrings(nullableScan))

    println(renderInts("".scan(42) { accumulator, value -> accumulator + value.code }))

    val tracked = CountingSequence("a\uD83D\uDE00")
    val trackedScan = tracked.scan(0) { accumulator, value -> accumulator + value.code }
    println("${renderInts(trackedScan)}:${tracked.lengthReads}:${tracked.getReads}")

    val shrinking = MutableSequence("abcd")
    val dynamicScan = shrinking.scan(0) { accumulator, value ->
        if (value == 'a') shrinking.visibleLength = 2
        accumulator + value.code
    }
    println(renderInts(dynamicScan))

    val indexedShrinking = MutableSequence("wxyz")
    val fixedIndexedScan = indexedShrinking.scanIndexed("") { index, accumulator, value ->
        if (index == 0) indexedShrinking.visibleLength = 2
        accumulator + index + value
    }
    println(renderStrings(fixedIndexedScan))

    println(directScanReturn("abc", 'b'))
    println(directScanReturn("abc", 'z'))
    println(safeScanReturn("abc", 'b'))
    println(safeScanReturn(null, 'b'))
    println(capturedScanReturn("abc", 'c'))
    println(namedIndexedScanReturn("abc", 'c'))
    println(throwingScan("abc"))
}
