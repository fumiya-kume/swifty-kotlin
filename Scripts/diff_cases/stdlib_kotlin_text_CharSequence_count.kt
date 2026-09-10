private class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override operator fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun main() {
    val string: String = "A😀"
    val builder: StringBuilder = StringBuilder("A😀")
    val custom = CountingCharSequence("A😀")

    println(string.count())
    println(builder.count())
    println("".count())
    println(custom.count())
    println(custom.lengthReads)

    val interfaceString: CharSequence = string
    val interfaceBuilder: CharSequence = builder
    val interfaceCustom: CharSequence = custom
    println(interfaceString.count())
    println(interfaceBuilder.count())
    println(interfaceCustom.count())
    println(custom.lengthReads)
}
