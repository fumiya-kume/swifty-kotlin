// KSP-1001: List-specific overloads must preserve the Kotlin stdlib return
// type while keeping the generic Iterable overload available.
fun main() {
    val values: List<String?> = listOf("a", "b")
    val checked: List<String> = values.requireNoNulls()
    println(checked)

    val iterable: Iterable<String?> = listOf("x", "y")
    val iterableChecked: Iterable<String> = iterable.requireNoNulls()
    println(iterableChecked)

    val indexed = listOf(0, 1, 2, 3)
    println(indexed.slice(1..2))
    println(indexed.slice(listOf(3, 1, 3)))

    try {
        listOf<String?>("a", null).requireNoNulls()
        println("unexpected")
    } catch (e: IllegalArgumentException) {
        println("null")
    }
}
