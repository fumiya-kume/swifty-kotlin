enum class Color(val rgb: Int) {
    RED(0xFF0000),
    GREEN(0x00FF00),
    BLUE(0x0000FF);
    
    companion object {
        fun fromRgb(rgb: Int): Color? = values.find { it.rgb == rgb }
    }
}

enum class Direction {
    NORTH, SOUTH, EAST, WEST;
    
    companion object {
        fun opposite(direction: Direction): Direction = when (direction) {
            NORTH -> SOUTH
            SOUTH -> NORTH
            EAST -> WEST
            WEST -> EAST
        }
    }
}

fun main() {
    // Test enum values and entries
    println("Color values:")
    Color.values().forEach { color ->
        println("  ${color.name} = ${color.rgb}")
    }
    
    println("\nDirection entries:")
    Direction.entries.forEach { direction ->
        println("  ${direction.name}")
    }
    
    // Test valueOf
    println("\nTesting valueOf:")
    println("Color.fromRgb(0xFF0000): ${Color.fromRgb(0xFF0000)}")
    println("Color.fromRgb(123456): ${Color.fromRgb(123456)}")
    
    // Test enum properties
    val red = Color.RED
    println("\nEnum properties:")
    println("RED.name: ${red.name}")
    println("RED.ordinal: ${red.ordinal}")
    println("RED.rgb: ${red.rgb}")
    
    // Test companion methods
    println("\nCompanion methods:")
    println("Direction.opposite(NORTH): ${Direction.opposite(Direction.NORTH)}")
    println("Direction.opposite(SOUTH): ${Direction.opposite(Direction.SOUTH)}")
}
