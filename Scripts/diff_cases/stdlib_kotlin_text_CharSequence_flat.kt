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
}
