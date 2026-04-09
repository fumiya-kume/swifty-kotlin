enum class Direction {
    NORTH,
    SOUTH,
}

fun main() {
    println(Direction.entries.toList())
    println(enumValues<Direction>().toList())
    println(enumValueOf<Direction>("NORTH"))
    println(Direction.SOUTH.name)
    println(Direction.SOUTH.ordinal)

    try {
        println(enumValueOf<Direction>("WEST"))
    } catch (e: Throwable) {
        println("invalid-enum-name")
    }
}
