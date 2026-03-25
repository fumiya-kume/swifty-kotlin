fun main() {
    sequenceOf(1, 2, 3).forEach { print(it) }
    println()

    val result = sequenceOf(1, 2, 3).flatMap { sequenceOf(it, it * 10) }.toList()
    println(result)
}
