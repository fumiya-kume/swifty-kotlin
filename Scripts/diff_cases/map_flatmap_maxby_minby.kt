fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map.flatMap { listOf(it.key, it.value.toString()) })
    println(map.maxByOrNull { it.value }?.key)
    println(map.minByOrNull { it.value }?.key)
    val emptyMap = emptyMap<String, Int>()
    println(emptyMap.maxByOrNull { it.value })
}
