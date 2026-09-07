private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var used = false
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        if (used) throw IllegalStateException("iterator reused")
        used = true
        iteratorCalls += 1
        return values.iterator()
    }
}

private class Key(private val id: Int, private val ignored: Int) {
    override fun equals(other: Any?): Boolean = other is Key && id == other.id
    override fun hashCode(): Int = id
}

fun main() {
    val direct = OneShotIterable(listOf(1, 2, 3))
    println(direct.contains(2))
    println("direct-iterators=${direct.iteratorCalls}")

    val operator = OneShotIterable(listOf(1, 2, 3))
    println(2 in operator)
    println("operator-iterators=${operator.iteratorCalls}")

    val missing = OneShotIterable(listOf(1, 2, 3))
    println(missing.contains(9))
    println("missing-iterators=${missing.iteratorCalls}")

    val empty = OneShotIterable(emptyList<Int>())
    println(1 !in empty)
    println("empty-iterators=${empty.iteratorCalls}")

    val nullable: Iterable<String?> = OneShotIterable(listOf(null, "value"))
    println(nullable.contains(null))

    val list: Iterable<Int> = listOf(1, 2, 3)
    println(list.contains(2))

    val set: Iterable<Int> = setOf(1, 2, 3)
    println(4 !in set)

    val keys: Iterable<Key> = OneShotIterable(listOf(Key(7, 1)))
    println(keys.contains(Key(7, 2)))
}
