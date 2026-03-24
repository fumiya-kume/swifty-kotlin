fun main() {
    val pairs = listOf(1 to "one", 2 to "two", 3 to "three")
    pairs.forEach { (num, name) -> println("$num -> $name") }
    val map = mapOf("x" to 10, "y" to 20)
    map.forEach { (k, v) -> println("$k: $v") }
    val indexed = listOf("a", "b", "c").withIndex()
    for ((i, v) in indexed) println("$i: $v")
}
