@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

class CollectionSizeTrackingIterable<T>(private val source: List<T>) : Iterable<T> {
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        return source.iterator()
    }
}

fun main() {
    val collection: Iterable<Int> = listOf(1, 2, 3)
    val empty: Iterable<String?> = emptyList()
    val unknown = CollectionSizeTrackingIterable(listOf("a", "b"))

    println(collection.collectionSizeOrNull())
    println(collection.collectionSizeOrDefault(-7))
    println(empty.collectionSizeOrNull())
    println(empty.collectionSizeOrDefault(-7))
    println(unknown.collectionSizeOrNull())
    println(unknown.collectionSizeOrDefault(-7))
    println(unknown.iteratorCalls)
}
