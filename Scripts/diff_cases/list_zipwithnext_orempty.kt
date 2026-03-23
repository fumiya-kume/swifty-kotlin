fun main() {
    // --- List.zipWithNext() ---
    val nums = listOf(1, 2, 3, 4, 5)
    println(nums.zipWithNext())

    // Single-element list
    val single = listOf(42)
    println(single.zipWithNext())

    // --- List.zipWithNext(transform) ---
    val diffs = nums.zipWithNext { a, b -> b - a }
    println(diffs)

    val words = listOf("a", "b", "c")
    val concat = words.zipWithNext { a, b -> a + b }
    println(concat)

    // --- List?.orEmpty() ---
    val nullList: List<Int>? = null
    println(nullList.orEmpty())
    println(nullList.orEmpty().size)

    val nonNullList: List<Int>? = listOf(1, 2, 3)
    println(nonNullList.orEmpty())
    println(nonNullList.orEmpty().size)

    // --- Map?.orEmpty() ---
    val nullMap: Map<String, Int>? = null
    println(nullMap.orEmpty())
    println(nullMap.orEmpty().size)

    val nonNullMap: Map<String, Int>? = mapOf("a" to 1)
    println(nonNullMap.orEmpty())
    println(nonNullMap.orEmpty().size)

    // --- String?.orEmpty() ---
    val nullStr: String? = null
    println(nullStr.orEmpty())
    println(nullStr.orEmpty().length)

    val nonNullStr: String? = "hello"
    println(nonNullStr.orEmpty())
    println(nonNullStr.orEmpty().length)
}
