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
    println(custom.flatMap { listOf(it) })
    println(custom.flatMap { listOf(it.code) })
    println(custom.flatMapIndexed { index, value -> listOf(index, value == 'a') })

    val destination: MutableList<Any?> = mutableListOf("seed")
    val returned = custom.flatMapTo(destination) { value ->
        if (value == 'a') listOf<Any?>(null, true) else emptyList<Any?>()
    }
    println(returned)
    println(returned === destination)

    val indexedDestination: MutableList<Any?> = mutableListOf("indexed")
    val indexedReturned = custom.flatMapIndexedTo(indexedDestination) { index, value ->
        listOf<Any?>(index, value)
    }
    println(indexedReturned)
    println(indexedReturned === indexedDestination)

    println(custom.toString())
    val counters = custom as CountingCharSequence
    println("reads=" + counters.lengthReads + "," + counters.getReads)

    val builder: CharSequence = StringBuilder("xy")
    println(builder.flatMap { listOf(it == 'x') })
    println("".flatMap<Any?> { emptyList() })

    // Every flat-family transform is inline. These callbacks return from the
    // enclosing function, so the ordinary tail marker must be unreachable.
    fun directFlatMap(source: CharSequence): String {
        source.flatMap<Char> { return "!" }
        return "?"
    }

    fun capturedFlatMapIndexed(source: CharSequence): String {
        val marker = "!"
        source.flatMapIndexed<Char> { _, _ -> return marker }
        return "?"
    }

    fun nullableFlatMapTo(source: CharSequence): String {
        val destination: MutableList<Char?> = mutableListOf()
        source.flatMapTo<Char?, MutableList<Char?>>(destination) { value ->
            if (value == 'a') return "!"
            listOf<Char?>(null)
        }
        return "?"
    }

    fun discardedFlatMapIndexedTo(source: CharSequence): String {
        val destination: MutableList<Char> = mutableListOf()
        source.flatMapIndexedTo<Char, MutableList<Char>>(destination) { index, _ ->
            if (index == 0) return "!"
            emptyList<Char>()
        }
        return "?"
    }

    println(directFlatMap(custom))
    println(capturedFlatMapIndexed(custom))
    println(nullableFlatMapTo(custom))
    println(discardedFlatMapIndexedTo(custom))
}
