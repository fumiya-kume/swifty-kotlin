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

private fun renderBooleans(values: List<Boolean>): String {
    val result = StringBuilder()
    var index = 0
    while (index < values.size) {
        if (index > 0) result.append('|')
        result.append(values[index])
        index++
    }
    return result.toString()
}

private fun renderChars(values: List<Char>): String {
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

private fun directFoldReturn(source: CharSequence, target: Char): Int {
    source.runningFold(0) { accumulator, value ->
        if (value == target) return 41
        accumulator + 1
    }
    return -1
}

private fun safeFoldReturn(source: CharSequence?, target: Char): Int {
    source?.runningFold(0) { accumulator, value ->
        if (value == target) return 42
        accumulator + 1
    }
    return -1
}

private fun capturedFoldReturn(source: CharSequence, target: Char): Int {
    val expected = target
    source.runningFold(0, operation = { accumulator, value ->
        if (value == expected) return 43
        accumulator + 1
    })
    return -1
}

private fun namedIndexedFoldReturn(source: CharSequence, target: Char): Int {
    source.runningFoldIndexed(0, operation = { index, accumulator, value ->
        if (value == target) return 44
        accumulator + 1
    })
    return -1
}

private fun directReduceReturn(source: CharSequence, target: Char): Char {
    source.runningReduce { accumulator, value ->
        if (value == target) return 'R'
        if (accumulator < value) value else accumulator
    }
    return '?'
}

private fun namedIndexedReduceReturn(source: CharSequence, target: Char): Char {
    source.runningReduceIndexed(operation = { index, accumulator, value ->
        if (index == 1 && value == target) return 'I'
        if (accumulator < value) value else accumulator
    })
    return '?'
}

private fun throwingFold(source: CharSequence): String {
    return try {
        source.runningFold(0) { accumulator, value ->
            if (value == 'b') throw IllegalStateException("stop-fold")
            accumulator + value.code
        }
        "completed"
    } catch (error: IllegalStateException) {
        error.message ?: "null"
    }
}

private fun throwingReduce(source: CharSequence): String {
    return try {
        source.runningReduce { accumulator, value ->
            if (value == 'b') throw IllegalStateException("stop-reduce")
            if (accumulator < value) value else accumulator
        }
        "completed"
    } catch (error: IllegalStateException) {
        error.message ?: "null"
    }
}

fun main() {
    val intFold = "abc".runningFold(0) { accumulator, value -> accumulator + value.code }
    println(renderInts(intFold))
    println("abc".runningFold(0) { accumulator, _ -> accumulator + 1 })
    println("abc".runningFoldIndexed(0) { index, accumulator, _ -> accumulator + index + 1 })
    println("abc".runningReduce { accumulator, value -> if (accumulator < value) value else accumulator })

    val booleanFold = "ab".runningFold(false) { accumulator, value -> accumulator || value == 'b' }
    println(renderBooleans(booleanFold))

    val nullableFold = "ab".runningFold<String?>(null) { accumulator, value ->
        if (accumulator == null) value.toString() else accumulator + value
    }
    println(renderNullableStrings(nullableFold))

    val indexedFold = "abc".runningFoldIndexed("") { index, accumulator, value ->
        accumulator + index + value
    }
    println(renderStrings(indexedFold))

    val charReduce = "abcd".runningReduce { accumulator, value ->
        if (accumulator < value) value else accumulator
    }
    println(renderChars(charReduce))

    val indexedReduce = "abcd".runningReduceIndexed { index, accumulator, value ->
        if (index % 2 == 0) value else accumulator
    }
    println(renderChars(indexedReduce))

    println(renderInts("".runningFold(42) { accumulator, value -> accumulator + value.code }))
    println(renderChars("".runningReduce { accumulator, _ -> accumulator }))

    val tracked = CountingSequence("a\uD83D\uDE00")
    val trackedFold = tracked.runningFold(0) { accumulator, value -> accumulator + value.code }
    println("${renderInts(trackedFold)}:${tracked.lengthReads}:${tracked.getReads}")

    val shrinking = MutableSequence("abcd")
    val dynamicFold = shrinking.runningFold(0) { accumulator, value ->
        if (value == 'a') shrinking.visibleLength = 2
        accumulator + value.code
    }
    println(renderInts(dynamicFold))

    val indexedShrinking = MutableSequence("wxyz")
    val fixedIndexedFold = indexedShrinking.runningFoldIndexed("") { index, accumulator, value ->
        if (index == 0) indexedShrinking.visibleLength = 2
        accumulator + index + value
    }
    println(renderStrings(fixedIndexedFold))

    val reduceShrinking = MutableSequence("abcd")
    val fixedReduce = reduceShrinking.runningReduce { accumulator, value ->
        if (value == 'a') reduceShrinking.visibleLength = 2
        if (accumulator < value) value else accumulator
    }
    println(renderChars(fixedReduce))

    println(directFoldReturn("abc", 'b'))
    println(directFoldReturn("abc", 'z'))
    println(safeFoldReturn("abc", 'b'))
    println(safeFoldReturn(null, 'b'))
    println(capturedFoldReturn("abc", 'c'))
    println(namedIndexedFoldReturn("abc", 'c'))
    println(directReduceReturn("abc", 'b'))
    println(namedIndexedReduceReturn("abc", 'b'))
    println(throwingFold("abc"))
    println(throwingReduce("abc"))
}
