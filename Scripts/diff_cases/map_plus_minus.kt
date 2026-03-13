fun main() {
    val map = mapOf("a" to 1, "b" to 2)
    val map2 = map + ("c" to 3)
    println(map2)
    val map3 = map2 - "b"
    println(map3)
    println(map)
}
