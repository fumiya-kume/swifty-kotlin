fun main() {
    val set = setOf(1, 2, 3)
    println(set.map { it * 2 })
    println(set.filter { it > 1 })
    set.forEach { print("$it ") }
    println()
    println(set.toList())
}
