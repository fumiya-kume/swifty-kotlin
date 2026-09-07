private class CustomCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun main() {
    val source: CharSequence = CustomCharSequence("a1B-2c")
    println(source.filter { it == 'a' || it == 'B' || it == 'c' })
    println(source.filterIndexed { index, _ -> index % 2 == 0 })
    println(source.filterNot { it == '-' })

    val destination = StringBuilder("prefix:")
    println(source.filterTo(destination) { it.isLetter() }.toString())

    val notDestination = StringBuilder("prefix:")
    println(source.filterNotTo(notDestination) { it == '-' }.toString())

    val indexedDestination = StringBuilder("prefix:")
    println(source.filterIndexedTo(indexedDestination) { index, _ -> index % 2 == 1 }.toString())
}
