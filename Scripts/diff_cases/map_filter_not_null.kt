fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3, "d" to 4)
    val result = map.filterNot { it.value % 2 == 0 }
    println(result)  // {a=1, c=3}

    val mapped = map.mapNotNull { if (it.value > 2) "${it.key}:${it.value}" else null }
    println(mapped)  // [c:3, d:4]
}
