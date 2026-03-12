fun main() {
    val map = mapOf("a" to 1, "b" to 2)
    println(map.getOrDefault("a", 0))
    println(map.getOrDefault("b", 0))
    println(map.getOrDefault("c", 0))
    println(map.getOrElse("a") { 99 })
    println(map.getOrElse("z") { 99 })
}
