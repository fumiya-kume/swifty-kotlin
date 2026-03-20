fun main() {
    // Basic UIntRange creation and contains
    val range = 1u..10u
    println(5u in range)
    println(15u in range)
    println(0u in range)
    println(1u in range)
    println(10u in range)
    println(5u !in range)

    // Empty range
    println((10u..1u).isEmpty())
    println((1u..10u).isEmpty())

    // UIntRange properties
    println((1u..5u).first)
    println((1u..5u).last)

    // UIntProgression with step
    println((1u..10u step 2).first)
    println((1u..10u step 2).last)
    println((1u..10u step 2).toList())
    println((1u..10u step 3).toList())

    // downTo
    println((10u downTo 1u).toList())
    println((10u downTo 1u step 3).first)
    println((10u downTo 1u step 3).last)
    println((10u downTo 1u step 3).toList())
    println((10u downTo 1u step 3).count())

    // forEach and map
    (1u..5u).forEach { print("$it ") }
    println()
    println((1u..5u).map { it * 2u })

    // for loop
    for (i in 1u..5u) print("$i ")
    println()
    for (i in 1u..10u step 2) print("$i ")
    println()
    for (i in 10u downTo 1u step 3) print("$i ")
    println()

    // reversed
    println((1u..5u).reversed().toList())

    // ULong range
    val ulongRange = 1UL..10UL
    println(5UL in ulongRange)
    println(15UL in ulongRange)
    println((1UL..10UL step 2).first)
    println((1UL..10UL step 2).last)
    println((10UL downTo 1UL step 3).toList())
    println((10UL downTo 1UL step 3).last)
    println((1UL..3UL).map { it })
    (1UL..3UL).forEach { print("$it;") }
    println()

    // sum and count
    println((1u..5u).sum())
    println((1u..5u).count())

    // until (exclusive end)
    println((1u..<5u).toList())

    // toString
    println(1u..5u)
    println(1u..10u step 2)
}
