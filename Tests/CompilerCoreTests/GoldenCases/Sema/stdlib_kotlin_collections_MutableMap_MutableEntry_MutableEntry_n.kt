package golden.sema

fun updateMutableEntry(values: MutableMap<String, Int>): Int {
    val entry = values.iterator().next()
    return entry.setValue(42)
}
