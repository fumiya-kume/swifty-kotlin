class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) throw IllegalStateException("one-shot iterable reused")
        consumed = true
        return values.iterator()
    }
}

fun main() {
    val associated = OneShotIterable(listOf(Pair("a", 1), Pair("b", 2), Pair("a", 3)))
    println(associated.associate { it })

    val associateBy = OneShotIterable(listOf("a", "b", "a"))
    println(associateBy.associateBy { it })

    val associateByTransformed = OneShotIterable(listOf("a", "bb", "a"))
    println(associateByTransformed.associateBy({ it }, { it.length }))

    val byToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToResult = OneShotIterable(listOf("a", "bb")).associateByTo(byToDestination) { it }
    println(byToResult === byToDestination)
    println(byToDestination)

    val byToTransformedDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToTransformedResult = OneShotIterable(listOf("a", "bb")).associateByTo(
        byToTransformedDestination,
        { it },
        { it.length }
    )
    println(byToTransformedResult === byToTransformedDestination)
    println(byToTransformedDestination)

    val toDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val toResult = OneShotIterable(listOf("a", "bb")).associateTo(toDestination) {
        Pair(it, it.length)
    }
    println(toResult === toDestination)
    println(toDestination)

    val associateWith = OneShotIterable(listOf("a", "bb", "a"))
    println(associateWith.associateWith { it.length })

    val withToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val withToResult = OneShotIterable(listOf("a", "bb")).associateWithTo(
        withToDestination
    ) { it.length }
    println(withToResult === withToDestination)
    println(withToDestination)
}
