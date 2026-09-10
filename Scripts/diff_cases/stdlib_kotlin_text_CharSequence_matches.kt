private class IndexedCharSequence(private val content: String) : CharSequence {
    private val units: List<Char> = content.toList()

    override val length: Int
        get() = units.size

    override fun get(index: Int): Char = units[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        if (startIndex == 0) content else content.substring(startIndex, endIndex)

    override fun toString(): String = "wrong-toString"
}

fun main() {
    val custom: CharSequence = IndexedCharSequence("alpha")
    println(custom.matches(Regex("^alpha$")))
    println(custom matches Regex("^alpha$"))
    println(custom.matches(regex = Regex("^alpha$")))
    println(custom.matches(Regex("^wrong-toString$")))

    val builder: CharSequence = StringBuilder("Alpha")
    println(builder matches Regex("(?i)^alpha$"))
    val unicodeBuilder: CharSequence = StringBuilder("A😀B")
    println(unicodeBuilder matches Regex("^A😀B$"))

    val empty: CharSequence = IndexedCharSequence("")
    println(empty matches Regex("^$"))

    println("alpha".matches(Regex("^alpha$")))
    val stringAsSequence: CharSequence = "alpha"
    println(stringAsSequence matches Regex("^alpha$"))
}
