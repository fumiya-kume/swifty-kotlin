class UserSequence(private val values: Sequence<Int>) : Sequence<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun UserSequence.flatMapTo(
    destination: MutableList<Int>,
    transform: (Int) -> Sequence<Int>
): MutableList<Int> {
    destination.add(700)
    return destination
}

fun main() {
    val source: Sequence<Int> = sequenceOf(1, 2, 3)

    val iterableDestination: MutableList<Int> = mutableListOf(99)
    val iterableReturned = source.flatMapTo(iterableDestination) { value -> listOf(value, value * 10) }
    println(iterableReturned)
    println(iterableReturned === iterableDestination)

    val sequenceDestination: MutableList<Int> = mutableListOf(88)
    val sequenceReturned = source.flatMapTo(sequenceDestination) { value -> sequenceOf(value, value * 100) }
    println(sequenceReturned)
    println(sequenceReturned === sequenceDestination)

    val numberDestination: MutableList<Number> = mutableListOf(77)
    val numberReturned = source.flatMapTo(numberDestination) { value -> sequenceOf(value * 2) }
    println(numberReturned)

    val indexedDestination: MutableList<Int> = mutableListOf(66)
    val indexedReturned = source.flatMapIndexedTo(indexedDestination) { index, value -> sequenceOf(index, value * 3) }
    println(indexedReturned)
    println(indexedReturned === indexedDestination)

    var emptyCalls = 0
    val emptyDestination: MutableList<Int> = mutableListOf(55)
    val emptyReturned = emptySequence<Int>().flatMapTo(emptyDestination) {
        emptyCalls += 1
        sequenceOf(1)
    }
    println(emptyReturned)
    println(emptyCalls)

    var visited = ""
    try {
        source.flatMapTo(mutableListOf<Int>()) { value ->
            visited += value.toString()
            if (value == 2) throw IllegalStateException("stop")
            sequenceOf(value)
        }
        println("returned")
    } catch (_: IllegalStateException) {
        println("caught:$visited")
    }

    val userDestination: MutableList<Int> = mutableListOf(44)
    val userReturned = UserSequence(sequenceOf(5)).flatMapTo(userDestination) { sequenceOf(it * 2) }
    println(userReturned)
}
