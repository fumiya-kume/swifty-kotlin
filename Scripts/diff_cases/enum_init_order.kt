enum class Planet { MERCURY, VENUS, EARTH, MARS, JUPITER, SATURN, URANUS, NEPTUNE }

fun main() {
    // Ordinals must match declaration order: 0, 1, 2, ...
    println(Planet.MERCURY.ordinal)
    println(Planet.VENUS.ordinal)
    println(Planet.EARTH.ordinal)
    println(Planet.MARS.ordinal)
    println(Planet.JUPITER.ordinal)
    println(Planet.SATURN.ordinal)
    println(Planet.URANUS.ordinal)
    println(Planet.NEPTUNE.ordinal)
}
