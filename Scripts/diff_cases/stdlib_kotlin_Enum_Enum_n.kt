enum class Direction { NORTH, SOUTH }
enum class Color { RED, BLUE }

fun main() {
    val north = Direction.NORTH
    val south = Direction.SOUTH

    println(north.compareTo(south))
    println(north.equals(north))
    println(north.equals(south))
    println(north.equals(Color.RED))
    println(north.equals(null))
    println(north.hashCode() == north.hashCode())
    println(north.name)
    println(south.ordinal)
    println(south.toString())
}
