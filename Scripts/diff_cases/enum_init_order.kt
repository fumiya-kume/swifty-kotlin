enum class Planet { MERCURY, VENUS, EARTH, MARS, JUPITER, SATURN, URANUS, NEPTUNE }

fun main() {
    // Ordinals must match declaration order: 0, 1, 2, ...
    println(Planet.MERCURY.ordinal)
    println(Planet.NEPTUNE.ordinal)

    // values() must return entries in declaration order
    val all = Planet.values()
    println(all[0])
    println(all[7])
    println(all.size)

    // valueOf must resolve to the correct entry
    println(Planet.valueOf("EARTH"))
    println(Planet.valueOf("EARTH").ordinal)

    // Single-entry enum edge case
    println(Planet.entries.first().name)
    println(Planet.entries.last().name)
}
