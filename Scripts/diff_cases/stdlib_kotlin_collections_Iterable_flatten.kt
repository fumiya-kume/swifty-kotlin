class OneShotIterable<T>(private val items: List<T>) : Iterable<T> {
    private var consumed = false
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        if (consumed) throw IllegalStateException("one-shot")
        consumed = true
        iteratorCalls = iteratorCalls + 1
        return items.iterator()
    }
}

class CountingIterable<T>(private val items: List<T>) : Iterable<T> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls = iteratorCalls + 1
        return items.iterator()
    }
}

class ThrowingIterable : Iterable<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var state = 0

        override fun hasNext(): Boolean = state < 2

        override fun next(): Int {
            if (state == 1) throw IllegalStateException("boom")
            state = state + 1
            return 7
        }
    }
}

fun main() {
    val firstInner = OneShotIterable(listOf(1, 2))
    val emptyInner = OneShotIterable(emptyList<Int>())
    val lastInner = OneShotIterable(listOf(3))
    val outerItems: List<Iterable<Int>> = listOf(firstInner, emptyInner, lastInner)
    val outer = OneShotIterable<Iterable<Int>>(outerItems)
    println(outer.flatten())
    println(outer.iteratorCalls)
    println(firstInner.iteratorCalls)
    println(emptyInner.iteratorCalls)
    println(lastInner.iteratorCalls)

    val nullable: Iterable<Iterable<String?>> = listOf(listOf(null, "x"), emptyList())
    println(nullable.flatten())

    val listNested: List<List<Int>> = listOf(listOf(4), listOf(5, 6))
    val iterableView: Iterable<Iterable<Int>> = listNested
    println(listNested.flatten())
    println(iterableView.flatten())

    val freshFirst = listOf(listOf(8)).flatten()
    val freshSecond = listOf(listOf(8)).flatten()
    println(freshFirst === freshSecond)

    val later = CountingIterable(listOf(9))
    try {
        val throwingItems: List<Iterable<Int>> = listOf(ThrowingIterable(), later)
        OneShotIterable<Iterable<Int>>(throwingItems).flatten()
        println("no-throw")
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(later.iteratorCalls)
}
