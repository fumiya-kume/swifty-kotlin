fun main() {
    val list = buildList { add(1); add(2); add(3) }
    println(list)
    val set = buildSet { add("a"); add("b"); add("a") }
    println(set)
    val map = buildMap { put("x", 1); put("y", 2) }
    println(map)
    println(emptyList<Int>())
    println(emptySet<String>())
    println(emptyMap<String, Int>())
    println(emptyList<Int>().size)
    println(emptyList<Int>().isEmpty())
}
