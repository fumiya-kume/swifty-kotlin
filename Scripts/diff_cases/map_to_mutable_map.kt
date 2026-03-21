fun main() {
    // Basic toMutableMap: creates independent mutable copy
    val original = mapOf("a" to 1, "b" to 2, "c" to 3)
    val mutable = original.toMutableMap()
    println(mutable)
    println(mutable.size)

    // Mutation does not affect original
    mutable["d"] = 4
    mutable["a"] = 99
    println(original)
    println(mutable)

    // toMutableMap on mutableMapOf result (creates a copy)
    val m1 = mutableMapOf("k1" to "v1")
    val m2 = m1.toMutableMap()
    m2["k2"] = "v2"
    println(m1)
    println(m2)

    // toMutableMap with remove operations
    val src = mapOf(1 to "one", 2 to "two", 3 to "three")
    val copy = src.toMutableMap()
    copy.remove(2)
    println(src)
    println(copy)

    // containsKey / containsValue on mutable copy
    val check = mapOf("hello" to 1, "world" to 2).toMutableMap()
    println(check.containsKey("hello"))
    println(check.containsValue(2))
    println(check.containsKey("missing"))
}
