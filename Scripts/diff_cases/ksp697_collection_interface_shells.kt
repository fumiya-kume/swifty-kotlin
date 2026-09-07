class CustomIterable(private val value: Int) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = listOf(value).iterator()
}

fun main() {
    val values: List<Int> = listOf(7, 8)
    println(values[0])
    println(values.iterator().next())
    println(CustomIterable(10).iterator().next())
}
