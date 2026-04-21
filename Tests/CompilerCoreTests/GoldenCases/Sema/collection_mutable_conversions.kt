fun main() {
    // Iterable<T>.toMutableList()
    val items: Iterable<Int> = listOf(1, 2, 3)
    val ml1: MutableList<Int> = items.toMutableList()
    ml1.add(4)
    println(ml1)

    // Iterable<T>.toMutableSet()
    val ms1: MutableSet<Int> = items.toMutableSet()
    ms1.add(4)
    println(ms1.contains(4))

    // Iterable<T>.toHashSet()
    val hs1: MutableSet<Int> = items.toHashSet()
    hs1.add(5)
    println(hs1.contains(5))

    // Collection<T>.toMutableList()
    val col: Collection<String> = listOf("a", "b", "c")
    val ml2: MutableList<String> = col.toMutableList()
    ml2.add("d")
    println(ml2)

    // Map<K,V>.toMutableMap()
    val map = mapOf("x" to 1, "y" to 2)
    val mm: MutableMap<String, Int> = map.toMutableMap()
    mm["z"] = 3
    println(mm.containsKey("z"))
}
