enum class Color { RED, GREEN, BLUE }

fun main() {
    println(enumValues<Color>().size)
    println(enumValueOf<Color>("GREEN"))
}
