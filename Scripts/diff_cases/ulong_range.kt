fun main() {
    // Basic ULongRange contains
    println(5UL in 1UL..10UL)
    println(0UL in 1UL..10UL)
    println(10UL in 1UL..10UL)
    println(11UL in 1UL..10UL)

    // first / last on inline range with step
    println((1UL..10UL step 2).first)
    println((1UL..10UL step 2).last)

    // downTo first / last
    println((10UL downTo 1UL step 3).first)
    println((10UL downTo 1UL step 3).last)

    // Iteration with for loop
    for (i in 1UL..5UL) print("$i ")
    println()

    // Iteration with step
    for (i in 0UL..10UL step 3) print("$i ")
    println()

    // downTo iteration
    for (i in 5UL downTo 1UL) print("$i ")
    println()

    // downTo with step iteration
    for (i in 10UL downTo 1UL step 2) print("$i ")
    println()

    // forEach
    (1UL..3UL).forEach { print("$it ") }
    println()

    // map and toList
    println((1UL..5UL).map { it * 2UL }.toList())

    // count
    println((1UL..10UL).count())
    println((1UL..10UL step 2).count())
    println((10UL downTo 1UL step 3).count())

    // Single element range iteration
    for (i in 5UL..5UL) print("$i ")
    println()

    // Large ULong values (beyond Int range)
    for (i in 4294967295UL..4294967300UL) print("$i ")
    println()

    // toString
    println(1UL..5UL)
    println(1UL..10UL step 2)
    println(10UL downTo 1UL step 3)
}
