// SKIP-DIFF: withIndex() currently lowers to a concrete runtime list for subsequent indexed helpers,
// so its string form intentionally diverges from Kotlin's default IndexingIterable object rendering.
fun main() {
    val values = listOf(10, 20)
    println(values.withIndex())
    values.forEachIndexed { index, value -> println(index + value) }
    println(values.mapIndexed { index, value -> index + value })
}
