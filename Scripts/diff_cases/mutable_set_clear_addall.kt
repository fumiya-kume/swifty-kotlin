fun main() {
    val set = mutableSetOf(1, 2, 3)
    println(set)
    set.addAll(listOf(3, 4, 5))
    println(set)
    set.addAll(setOf(5, 6))
    println(set)
    set.clear()
    println(set)
}
