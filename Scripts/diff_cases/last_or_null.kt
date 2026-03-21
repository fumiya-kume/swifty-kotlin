fun main() {
    // 1. Basic lastOrNull on non-empty list
    val nums = listOf(10, 20, 30)
    println(nums.lastOrNull())

    // 2. lastOrNull on single-element list
    val single = listOf(42)
    println(single.lastOrNull())

    // 3. lastOrNull on mutableListOf
    val mutable = mutableListOf(1, 2, 3)
    println(mutable.lastOrNull())

    // 4. lastOrNull on list of strings
    val strings = listOf("hello", "world")
    println(strings.lastOrNull())

    // 5. Chained: map then lastOrNull
    val result = listOf(1, 2, 3).map { it * 10 }.lastOrNull()
    println(result)

    // 6. Chained: filter then lastOrNull
    val filtered = listOf(1, 2, 3, 4, 5).filter { it > 3 }.lastOrNull()
    println(filtered)
}
