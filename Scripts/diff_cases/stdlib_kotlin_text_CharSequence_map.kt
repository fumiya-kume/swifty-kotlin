private class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0
    var getReads: Int = 0

    override val length: Int
        get() {
            lengthReads += 1
            return value.length
        }

    override fun get(index: Int): Char {
        getReads += 1
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)

    override fun toString(): String = "different:$value"
}

fun main() {
    val custom: CharSequence = CountingCharSequence("ab")
    println(custom.mapIndexedNotNull<Char> { _, value -> if (value == 'a') value else null })
    println(custom.mapIndexedNotNull<Int> { index, _ -> if (index == 1) index else null })

    val indexedNotNullDestination: MutableList<Any?> = mutableListOf("indexed-null-seed")
    val indexedNotNullReturned = custom.mapIndexedNotNullTo<Char, MutableList<Any?>>(indexedNotNullDestination) { _, value ->
        if (value == 'a') value else null
    }
    println(indexedNotNullReturned)
    println(indexedNotNullReturned === indexedNotNullDestination)

    val indexedDestination: MutableList<Any?> = mutableListOf("indexed-seed")
    val indexedReturned = custom.mapIndexedTo<Char, MutableList<Any?>>(indexedDestination) { _, value -> value }
    println(indexedReturned)
    println(indexedReturned === indexedDestination)

    val notNullDestination: MutableList<Any?> = mutableListOf("not-null-seed")
    val notNullReturned = custom.mapNotNullTo<Boolean, MutableList<Any?>>(notNullDestination) { value ->
        if (value == 'b') true else null
    }
    println(notNullReturned)
    println(notNullReturned === notNullDestination)

    val mapDestination: MutableList<Any?> = mutableListOf("map-seed")
    val mapReturned = custom.mapTo<Int, MutableList<Any?>>(mapDestination) { value -> value.code }
    println(mapReturned)
    println(mapReturned === mapDestination)

    println(custom.toString())
    val counters = custom as CountingCharSequence
    println("reads=" + counters.lengthReads + "," + counters.getReads)

    val builder: CharSequence = StringBuilder("xy")
    val builderDestination: MutableList<Boolean> = mutableListOf()
    val builderReturned = builder.mapTo<Boolean, MutableList<Boolean>>(builderDestination) { value: Char -> value == 'x' }
    println(builderReturned)
    println("".mapIndexedNotNull<Int> { _, _ -> null })

    // Inline transform returns must target the enclosing function, including
    // captured values and nullable transform paths. The result is discarded
    // so an accidental callback return cannot be hidden by a later value.
    fun directMapTo(source: CharSequence): String {
        val destination: MutableList<Char> = mutableListOf()
        source.mapTo<Char, MutableList<Char>>(destination) { return "!" }
        return "?"
    }

    fun capturedMapIndexedTo(source: CharSequence): String {
        val marker = "!"
        val destination: MutableList<Char> = mutableListOf()
        source.mapIndexedTo<Char, MutableList<Char>>(destination) { _, _ -> return marker }
        return "?"
    }

    fun nullableMapNotNullTo(source: CharSequence): String {
        val destination: MutableList<Char> = mutableListOf()
        source.mapNotNullTo<Char, MutableList<Char>>(destination) { value ->
            if (value == 'a') return "!"
            null
        }
        return "?"
    }

    fun discardedMapIndexedNotNull(source: CharSequence): String {
        source.mapIndexedNotNull<Char> { index, _ ->
            if (index == 0) return "!"
            null
        }
        return "?"
    }

    println(directMapTo(custom))
    println(capturedMapIndexedTo(custom))
    println(nullableMapNotNullTo(custom))
    println(discardedMapIndexedNotNull(custom))
}
