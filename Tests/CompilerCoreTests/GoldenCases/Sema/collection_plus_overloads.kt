// RF-FIXTURE-016: Collection.plus overloads — element / Iterable / Sequence /
// Array operands and the plusElement alias all produce List<T>.
package golden.sema

fun collectionPlus(
    values: Collection<Int>,
    element: Int,
    others: List<Int>,
    sequence: Sequence<Int>,
    array: Array<Int>
) {
    val plusElement = values + element
    val checkedElement: List<Int> = plusElement
    val plusIterable = values + others
    val checkedIterable: List<Int> = plusIterable
    val plusSequence = values + sequence
    val checkedSequence: List<Int> = plusSequence
    val plusArray = values + array
    val checkedArray: List<Int> = plusArray
    val plusElementAlias = values.plusElement(element)
    val checkedAlias: List<Int> = plusElementAlias
}
