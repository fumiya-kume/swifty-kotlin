fun main() {
    // Basic unzip of List<Pair<Int, String>>
    val pairs = listOf(Pair(1, "a"), Pair(2, "b"), Pair(3, "c"))
    val (nums, strs) = pairs.unzip()
    println(nums)
    println(strs)

    // Unzip empty list
    val empty = emptyList<Pair<Int, String>>()
    val (emptyFirst, emptySecond) = empty.unzip()
    println(emptyFirst)
    println(emptySecond)

    // Unzip single element
    val single = listOf(Pair(42, "hello"))
    val (singleFirst, singleSecond) = single.unzip()
    println(singleFirst)
    println(singleSecond)

    // Unzip with Pair constructed via `to`
    val toPairs = listOf(1 to "x", 2 to "y", 3 to "z")
    val result = toPairs.unzip()
    println(result.first)
    println(result.second)

    // Unzip with nullable values
    val nullablePairs = listOf(Pair(1, null), Pair(2, "b"), Pair(3, null))
    val (nullNums, nullStrs) = nullablePairs.unzip()
    println(nullNums)
    println(nullStrs)

    // Unzip with both nullable types
    val bothNullable = listOf(Pair<Int?, String?>(null, "a"), Pair(2, null))
    val (bn1, bn2) = bothNullable.unzip()
    println(bn1)
    println(bn2)

    // Unzip result type check via toString
    val pairList = listOf(Pair(true, 3.14), Pair(false, 2.72))
    val unzipped = pairList.unzip()
    println(unzipped)
    println(unzipped.first)
    println(unzipped.second)
}
