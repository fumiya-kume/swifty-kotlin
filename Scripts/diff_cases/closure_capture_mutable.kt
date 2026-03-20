// SKIP-DIFF  -- mutable capture requires Ref boxing (not yet implemented)
fun main() {
    // Mutable capture via forEach
    var total = 0
    val nums = listOf(1, 2, 3, 4, 5)
    nums.forEach { total += it }
    println(total)

    // Mutable capture in nested scope - string concat
    var result = ""
    listOf("a", "b", "c").forEach { result += it }
    println(result)

    // Mutable capture with map (side effect in map)
    var count = 0
    val mapped = listOf(10, 20, 30).map {
        count++
        it * 2
    }
    println(mapped)
    println(count)
}
