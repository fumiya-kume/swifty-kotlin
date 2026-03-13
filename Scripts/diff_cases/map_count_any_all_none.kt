fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map.count { it.value > 1 })
    println(map.any { it.value > 2 })
    println(map.all { it.value > 0 })
    println(map.none { it.value > 5 })
}
