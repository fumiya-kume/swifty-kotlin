package golden.sema

fun inspect(values: Set<Int?>): String {
    val size = values.size
    val empty = values.isEmpty()
    val containsNull = values.contains(null)
    val iteratorHasNext = values.iterator().hasNext()
    return "$size:$empty:$containsNull:$iteratorHasNext"
}
