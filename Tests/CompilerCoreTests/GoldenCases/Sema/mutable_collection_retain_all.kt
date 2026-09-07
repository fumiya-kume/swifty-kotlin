// RF-FIXTURE-017: MutableCollection.retainAll overloads for Iterable /
// Sequence / Array / Collection operands.
private class StableIterable(private val values: List<Int>) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun retainAllOverloads(
    target: MutableCollection<Int>,
    iterable: Iterable<Int>,
    sequence: Sequence<Int>,
    array: Array<Int>,
    collection: Collection<Int>
) {
    val fromIterable = target.retainAll(iterable)
    val checkedIterable: Boolean = fromIterable
    val fromSequence = target.retainAll(sequence)
    val checkedSequence: Boolean = fromSequence
    val fromArray = target.retainAll(array)
    val checkedArray: Boolean = fromArray
    val fromCollection = target.retainAll(collection)
    val checkedCollection: Boolean = fromCollection
}
