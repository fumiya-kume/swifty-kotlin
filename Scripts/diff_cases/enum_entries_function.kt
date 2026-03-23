enum class Color { RED, GREEN, BLUE }

fun main() {
    val entries = enumEntries<Color>()
    println(entries)
    println(entries.size)
}
