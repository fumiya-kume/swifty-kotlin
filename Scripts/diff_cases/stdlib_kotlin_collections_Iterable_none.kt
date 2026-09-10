private class TrackingIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        return values.iterator()
    }
}

fun main() {
    val customEmpty = TrackingIterable(emptyList<Int>())
    println(customEmpty.none())
    println("custom-empty-iterators=${customEmpty.iteratorCalls}")

    val customMatch = TrackingIterable(listOf(1, 2, 3))
    println(customMatch.none { it == 2 })
    println("custom-match-iterators=${customMatch.iteratorCalls}")

    val customNoMatch = TrackingIterable(listOf(1, 2, 3))
    println(customNoMatch.none { it > 3 })
    println("custom-no-match-iterators=${customNoMatch.iteratorCalls}")

    val collection: Iterable<Int> = listOf(1, 2, 3)
    println(collection.none())
    println(collection.none { it == 2 })

    val emptyCollection: Iterable<Int> = emptyList()
    println(emptyCollection.none { true })

    val nullable: Iterable<String?> = TrackingIterable(listOf(null, "value"))
    println(nullable.none { it == null })
}
