fun main() {
    // 1. Basic: Map.minus(key)
    val base = mapOf("a" to 1, "b" to 2, "c" to 3, "d" to 4)
    val r1 = base - "b"
    println(r1)

    // 2. Removing a key that does not exist
    val r2 = base - "z"
    println(r2)

    // 3. Original map is unchanged (immutability)
    println(base)

    // 4. Chained minus
    val r9 = base - "a" - "d"
    println(r9)

    // 5. Map with Int keys
    val intMap = mapOf(1 to "one", 2 to "two", 3 to "three")
    val r11 = intMap - 2
    println(r11)

    // 6. Size after minus
    val r13 = base - "a"
    println(r13.size)

    // 7. containsKey after minus
    val r14 = base - "b"
    println(r14.containsKey("b"))
    println(r14.containsKey("a"))
}
