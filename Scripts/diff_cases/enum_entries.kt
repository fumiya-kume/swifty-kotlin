enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    // entries returns all enum constants in declaration order
    for (entry in Direction.entries) {
        println(entry)
    }
    // entries.size matches the number of constants
    println(Direction.entries.size)
}
