enum class Color { RED, GREEN, BLUE }

fun main() {
    // enumValues<T>() returns Array<T> on Kotlin JVM
    val vals = enumValues<Color>()
    println(vals.size)
    println(vals[0])

    // Color.entries returns EnumEntries<Color> (extends List<Color>)
    val ents = Color.entries
    println(ents.size)
    println(ents[0])

    // Color.values() returns Array<Color> on Kotlin JVM
    val vs = Color.values()
    println(vs.size)
    println(vs[0])
}
