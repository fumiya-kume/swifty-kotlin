open class Animal(val weight: Int)

class Cat(weight: Int) : Animal(weight)

fun testGroupingAggregateTo(
    values: List<String>,
    destination: MutableMap<Any?, String>
): MutableMap<Any?, String> {
    return values.groupingBy { it.length }.aggregateTo(destination) { _, accumulator: String?, element, first ->
        if (first) element else accumulator ?: element
    }
}

fun testGroupingEachCountTo(
    values: List<String>,
    destination: MutableMap<Any?, Int>
): MutableMap<Any?, Int> = values.groupingBy { it.length }.eachCountTo(destination)

fun testGroupingFoldTo(
    values: List<String>,
    destination: MutableMap<Any?, Int>
): MutableMap<Any?, Int> = values.groupingBy { it.length }.foldTo(
    destination,
    0
) { accumulator, element -> accumulator + element.length }

fun testGroupingFoldToWithSelector(
    values: List<String>,
    destination: MutableMap<Any?, Int>
): MutableMap<Any?, Int> = values.groupingBy { it.length }.foldTo(
    destination,
    { key, element -> key + element.length },
    { key, accumulator, element -> accumulator + key + element.length }
)

fun testGroupingReduceTo(
    values: List<Cat>,
    destination: MutableMap<Any?, Animal>
): MutableMap<Any?, Animal> = values.groupingBy { it.weight }.reduceTo(destination) { _, accumulator: Animal, element ->
    if (element.weight > accumulator.weight) accumulator else accumulator
}
