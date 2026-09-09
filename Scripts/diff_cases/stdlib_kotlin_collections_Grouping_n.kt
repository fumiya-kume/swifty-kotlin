open class Animal(val weight: Int)

class Cat(weight: Int) : Animal(weight)

fun main() {
    val values = listOf("a", "bb", "ccc", "dd")

    val aggregateDestination: MutableMap<Any?, String> =
        mutableMapOf<Any?, String>("seed" to "keep")
    val aggregate = values.groupingBy { it.length }.aggregateTo(aggregateDestination) {
        _, accumulator: String?, element, first ->
        if (first) element else accumulator ?: element
    }
    println("aggregateSame=${aggregate === aggregateDestination}")
    println("aggregate=${aggregate[1]}:${aggregate[2]}:${aggregate[3]}")

    val countDestination: MutableMap<Any?, Int> = mutableMapOf<Any?, Int>(2 to 10)
    val counts = values.groupingBy { it.length }.eachCountTo(countDestination)
    println("countSame=${counts === countDestination}")
    println("counts=${counts[1]}:${counts[2]}:${counts[3]}")

    val foldDestination: MutableMap<Any?, Int> = mutableMapOf<Any?, Int>(2 to 100)
    val folded = values.groupingBy { it.length }.foldTo(foldDestination, 0) { accumulator, element ->
        accumulator + element.length
    }
    println("foldSame=${folded === foldDestination}")
    println("fold=${folded[1]}:${folded[2]}:${folded[3]}")

    val selectorDestination: MutableMap<Any?, Int> = mutableMapOf<Any?, Int>(2 to 100)
    val selectorFolded = values.groupingBy { it.length }.foldTo(
        selectorDestination,
        { key, element -> key + element.length },
        { key, accumulator, element -> accumulator + key + element.length }
    )
    println("selectorSame=${selectorFolded === selectorDestination}")
    println("selector=${selectorFolded[1]}:${selectorFolded[2]}:${selectorFolded[3]}")

    val cats = listOf(Cat(1), Cat(3), Cat(2))
    val reduceDestination: MutableMap<Any?, Animal> =
        mutableMapOf<Any?, Animal>("seed" to Cat(99))
    val reduced = cats.groupingBy { it.weight % 2 }.reduceTo(reduceDestination) {
        _, accumulator: Animal, _ -> accumulator
    }
    println("reduceSame=${reduced === reduceDestination}")
    println("reduce=${reduced[1]?.weight}:${reduced[0]?.weight}")
}
