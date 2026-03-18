fun main() {
    val range = 1u..10u
    println(5u in range)
    println(15u in range)
    println((1u..10u step 2).first)
    println((1u..10u step 2).last)
    println((10u downTo 1u step 3).count())
    println((1u..5u).map { it }.toList())
    (1u..3u).forEach { print("$it,") }
    println()

    val ulongRange = 1UL..10UL
    println(5UL in ulongRange)
    println((1UL..10UL step 2).first)
    println((10UL downTo 1UL step 3).last)
    println((1UL..3UL).map { it }.toList())
    (1UL..3UL).forEach { print("$it;") }
    println()

    for (i in 1u..5u) print("$i ")
    println()
}
