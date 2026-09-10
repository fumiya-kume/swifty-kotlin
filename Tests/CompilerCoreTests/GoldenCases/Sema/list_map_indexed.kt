// RF-FIXTURE-009: List.mapIndexed passes (index, element) to the lambda and
// returns List<R>.

fun indexed(values: List<String>) {
    val result = values.mapIndexed { index, item ->
        val checkedIndex: Int = index
        val checkedItem: String = item
        index
    }
    val checked: List<Int> = result
}
