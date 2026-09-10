// RF-FIXTURE-017: MutableCollection.addAll / plusAssign overloads for
// Iterable / Sequence / Array / element operands.
private class StableIterable(private val values: List<Int>) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun addAllOverloads(
    target: MutableCollection<Int>,
    iterable: Iterable<Int>,
    sequence: Sequence<Int>,
    array: Array<Int>
) {
    val fromIterable = target.addAll(iterable)
    val checkedIterable: Boolean = fromIterable
    val fromSequence = target.addAll(sequence)
    val checkedSequence: Boolean = fromSequence
    val fromArray = target.addAll(array)
    val checkedArray: Boolean = fromArray
}

fun plusAssignOverloads(target: MutableCollection<Int>, element: Int) {
    target += element
    target += StableIterable(listOf(3))
    target += sequenceOf(4)
    target += arrayOf(5)
}
