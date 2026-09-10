// RF-FIXTURE-017: MutableCollection.remove / removeAll / minusAssign overloads
// for element (incl. null) and Iterable / Sequence / Array / Collection
// operands.
private class StableIterable(private val values: List<Int>) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun removeElement(target: MutableCollection<Int>, element: Int) {
    val removed = target.remove(element)
    val checked: Boolean = removed
}

fun removeNullableElement(target: MutableCollection<Int?>, element: Int?) {
    val removed = target.remove(element)
    val checked: Boolean = removed
}

fun minusAssignOverloads(target: MutableCollection<Int>, element: Int) {
    target -= element
    target -= StableIterable(listOf(3))
    target -= sequenceOf(4)
    target -= arrayOf(5)
}

fun removeAllOverloads(
    target: MutableCollection<Int>,
    iterable: Iterable<Int>,
    sequence: Sequence<Int>,
    array: Array<Int>,
    collection: Collection<Int>
) {
    val fromIterable = target.removeAll(iterable)
    val checkedIterable: Boolean = fromIterable
    val fromSequence = target.removeAll(sequence)
    val checkedSequence: Boolean = fromSequence
    val fromArray = target.removeAll(array)
    val checkedArray: Boolean = fromArray
    val fromCollection = target.removeAll(collection)
    val checkedCollection: Boolean = fromCollection
}
