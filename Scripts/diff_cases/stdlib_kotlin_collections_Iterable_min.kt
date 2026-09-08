private class OneShotIterable(private val items: List<Int>) : Iterable<Int> {
    private var consumed = false

    override fun iterator(): Iterator<Int> {
        if (consumed) return emptyList<Int>().iterator()
        consumed = true
        return items.iterator()
    }
}

private class Box(val key: Int, val label: String)

private fun exercise(
    values: Iterable<Int>,
    doubles: Iterable<Double>,
    floats: Iterable<Float>,
    boxes: Iterable<Box>,
    nullableValues: Iterable<String?>,
    singleton: Iterable<Int>,
    oneShot: Iterable<Int>,
    empty: Iterable<Int>
) {
    println(values.min())
    println(values.minOrNull())
    println(values.minBy { it })
    println(values.minByOrNull { it })
    println(values.minOf { it })
    println(values.minOfOrNull { it })

    println(doubles.min())
    println(floats.min())
    println(doubles.minOrNull())
    println(floats.minOrNull())
    println(doubles.minOf { it })
    println(floats.minOf { it })
    println(doubles.minOfOrNull { it })
    println(floats.minOfOrNull { it })

    val numberComparator: Comparator<Number> = Comparator { left, right ->
        left.toDouble().compareTo(right.toDouble())
    }
    println(values.minWith(numberComparator))
    println(values.minWithOrNull(numberComparator))
    println(values.minOfWith(numberComparator) { it.toDouble() })
    println(values.minOfWithOrNull(numberComparator) { it.toDouble() })

    println(boxes.minBy { it.key }.label)
    println(boxes.minByOrNull { it.key }?.label)
    println(nullableValues.minByOrNull { it?.length ?: -1 })

    var selectorCalls = 0
    println(singleton.minByOrNull {
        selectorCalls += 1
        it
    })
    println(selectorCalls)

    println(oneShot.minOrNull())
    println(oneShot.minOrNull())

    val nanValues: Iterable<Double> = listOf(Double.NaN, 1.0)
    println(nanValues.min().isNaN())
    val signedZeros: Iterable<Double> = listOf(0.0, -0.0)
    println(1.0 / signedZeros.min())
    val infinities: Iterable<Double> = listOf(Double.POSITIVE_INFINITY, 4.0)
    println(infinities.min())

    try {
        empty.min()
    } catch (e: NoSuchElementException) {
        println("min threw")
    }
    println(empty.minOrNull())
}

fun main() {
    exercise(
        listOf(3, 1, 2, 1),
        listOf(3.0, 1.0, 2.0),
        listOf(3.0f, 1.0f, 2.0f),
        listOf(Box(2, "first"), Box(1, "second"), Box(1, "tie")),
        listOf(null, "a", "bb"),
        listOf(7),
        OneShotIterable(listOf(4, 2, 3)),
        emptyList()
    )
}
