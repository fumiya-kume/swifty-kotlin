// RF-FIXTURE-016: Collection queries — containsAll / count / indices.
package golden.sema

fun collectionQueries(values: Collection<Int>, other: Collection<Int>) {
    val containsAll = values.containsAll(other)
    val checkedAll: Boolean = containsAll
    val count = values.count()
    val checkedCount: Int = count
    val indices = values.indices
    val checkedIndices: IntRange = indices
}
