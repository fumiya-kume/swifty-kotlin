// RF-FIXTURE-005: generic Array<T>.toList() returns List<T> and size stays Int.
package golden.sema

fun genericArrayList(objects: Array<Int>) {
    val copy = objects.toList()
    val checked: List<Int> = copy
    val size = objects.size
    val checkedSize: Int = size
}
