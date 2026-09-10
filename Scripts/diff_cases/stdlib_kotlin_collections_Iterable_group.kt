class OneShotIterable<T>(private val items: List<T>) : Iterable<T> {
    private var consumed = false
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        if (consumed) throw IllegalStateException("iterator reused")
        consumed = true
        iteratorCalls += 1
        return items.iterator()
    }
}

class ThrowingIterable : Iterable<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var state = 0

        override fun hasNext(): Boolean = state < 2

        override fun next(): Int {
            if (state == 1) throw IllegalStateException("next failed")
            state += 1
            return 7
        }
    }
}

fun main() {
    var keyCalls = 0
    val grouped = OneShotIterable(listOf(3, 1, 4, 2, 5)).groupBy {
        keyCalls += 1
        it % 2
    }
    println(grouped.keys)
    println(grouped[1])
    println(grouped[0])
    println(keyCalls)

    var valueCalls = 0
    val transformed = OneShotIterable(listOf(1, 2, 3, 4)).groupBy(
        { it % 2 },
        {
            valueCalls += 1
            "v=$it"
        }
    )
    println(transformed[1])
    println(transformed[0])
    println(valueCalls)

    val destination: MutableMap<Any, MutableList<Int>> = mutableMapOf(
        "seed" to mutableListOf(99)
    )
    val returned = OneShotIterable(listOf(1, 3, 2)).groupByTo(destination) { it % 2 }
    println(returned === destination)
    println(destination["seed"])
    println(destination[1])
    println(destination[0])

    val transformedDestination: MutableMap<Any, MutableList<Int>> = mutableMapOf()
    OneShotIterable(listOf(1, 2, 3)).groupByTo(
        transformedDestination,
        { if (it % 2 == 0) "even" else "odd" },
        { it * 10 }
    )
    println(transformedDestination["odd"])
    println(transformedDestination["even"])

    val stringGroups: Iterable<String> = listOf("a", "b", "a")
    val groupedStrings = stringGroups.groupBy { it }
    println(groupedStrings)
    println(groupedStrings["a"])

    println(OneShotIterable(emptyList<Int>()).groupBy { it }.keys)

    try {
        ThrowingIterable().groupBy { it }
        println("no-throw")
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
