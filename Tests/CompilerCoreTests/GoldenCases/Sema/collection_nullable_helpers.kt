// RF-FIXTURE-016: Collection<T>? — isNullOrEmpty / orEmpty on a nullable
// receiver.
package golden.sema

fun collectionNullableHelpers(values: Collection<Int>?) {
    val nullOrEmpty = values.isNullOrEmpty()
    val checkedNullOrEmpty: Boolean = nullOrEmpty
    val orEmpty = values.orEmpty()
    val checkedOrEmpty: Collection<Int> = orEmpty
}
