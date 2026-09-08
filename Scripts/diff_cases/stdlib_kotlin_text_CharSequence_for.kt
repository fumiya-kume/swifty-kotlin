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

private fun collect(source: CharSequence): String {
    val result = StringBuilder()
    source.forEach { result.append(it.code).append(':') }
    return result.toString()
}

private fun collectIndexed(source: CharSequence): String {
    val result = StringBuilder()
    source.forEachIndexed { index, value -> result.append(index).append('=').append(value.code).append(';') }
    return result.toString()
}

private fun directReturn(source: CharSequence, target: Char): Char {
    source.forEach { if (it == target) return it }
    return '?'
}

private fun safeReturn(source: CharSequence?, target: Char): Char {
    source?.forEach { if (it == target) return it }
    return '?'
}

private fun capturedReturn(source: CharSequence, target: Char): Char {
    val expected = target
    source.forEach { if (it == expected) return it }
    return '?'
}

private fun namedReturn(source: CharSequence, target: Char): Char {
    source.forEach(action = { if (it == target) return it })
    return '?'
}

private fun namedIndexedReturn(source: CharSequence): Char {
    source.forEachIndexed(action = { index, value -> if (index == 1) return value })
    return '?'
}

private fun throwing(source: CharSequence): String {
    val visited = StringBuilder()
    try {
        source.forEach { value ->
            if (value == 'b') throw IllegalStateException("stop-forEach")
            visited.append(value)
        }
    } catch (error: IllegalStateException) {
        visited.append('|').append(error.message ?: "null")
    }
    return visited.toString()
}

private fun throwingIndexed(source: CharSequence): String {
    val visited = StringBuilder()
    try {
        source.forEachIndexed { index, value ->
            if (index == 1) throw IllegalStateException("stop-forEachIndexed")
            visited.append(value)
        }
    } catch (error: IllegalStateException) {
        visited.append('|').append(error.message ?: "null")
    }
    return visited.toString()
}

fun main() {
    val utf16: CharSequence = "\uD83D\uDE00"
    println(collect(utf16))
    println(collectIndexed(utf16))

    val tracked = CountingSequence("a\uD83D\uDE00")
    println(collect(tracked))
    println("${tracked.lengthReads}:${tracked.getReads}")

    val shrinking = MutableSequence("abcd")
    val shrinkVisited = StringBuilder()
    shrinking.forEach {
        shrinkVisited.append(it)
        if (it == 'a') shrinking.visibleLength = 2
    }
    println(shrinkVisited.toString())

    val indexedShrinking = MutableSequence("wxyz")
    val indexedVisited = StringBuilder()
    indexedShrinking.forEachIndexed { index, value ->
        indexedVisited.append(index).append(value)
        if (index == 0) indexedShrinking.visibleLength = 3
    }
    println(indexedVisited.toString())

    val growing = StringBuilder("ab")
    val grownVisited = StringBuilder()
    growing.forEach {
        grownVisited.append(it)
        if (it == 'a') growing.append('c')
    }
    println(grownVisited.toString())

    println(directReturn("abc", 'b'))
    println(directReturn("abc", 'z'))
    println(safeReturn("abc", 'b'))
    println(safeReturn(null, 'b'))
    println(capturedReturn("abc", 'c'))
    println(namedReturn("abc", 'c'))
    println(namedIndexedReturn("abc"))
    println(throwing("abc"))
    println(throwingIndexed("abc"))
}
