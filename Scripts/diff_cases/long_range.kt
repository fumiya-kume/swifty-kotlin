fun main() {
    // Basic LongRange creation via rangeTo
    val range = 1L..10L
    println(range.first)
    println(range.last)

    // Containment
    println(5L in range)
    println(15L in range)
    println(0L in range)
    println(5L !in range)

    // isEmpty
    println((10L..1L).isEmpty())
    println((1L..10L).isEmpty())

    // firstOrNull / lastOrNull
    println((1L..5L).firstOrNull())
    println((1L..5L).lastOrNull())
    println((10L..1L).firstOrNull())
    println((10L..1L).lastOrNull())

    // Properties
    println((1L..5L).first)
    println((1L..5L).last)

    // Step
    println((1L..10L step 2).first)
    println((1L..10L step 2).last)
    println((1L..10L step 2).toList())
    println((1L..10L step 3).toList())

    // downTo
    println((10L downTo 1L).toList())
    println((10L downTo 1L step 3).toList())

    // reversed
    println((1L..5L).reversed().toList())

    // for loop
    for (i in 1L..5L) print("$i ")
    println()
    for (i in 1L..10L step 2) print("$i ")
    println()

    // forEach and map
    (1L..5L).forEach { print("$it ") }
    println()
    println((1L..5L).map { it * 2L })
}
