fun main() {
    val map = mutableMapOf("a" to 1, "b" to 2)
    println(map.getOrPut("a") { 99 })
    println(map.getOrPut("c") { 3 })
    println(map)
}
