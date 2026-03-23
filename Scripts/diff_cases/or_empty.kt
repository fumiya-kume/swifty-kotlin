fun main() {
    // Map?.orEmpty()
    val nullMap: Map<String, Int>? = null
    val emptyFromNull = nullMap.orEmpty()
    println(emptyFromNull)
    println(emptyFromNull.size)

    val nonNullMap: Map<String, Int>? = mapOf("a" to 1, "b" to 2)
    val kept = nonNullMap.orEmpty()
    println(kept)
    println(kept.size)

    // List?.orEmpty()
    val nullList: List<Int>? = null
    val emptyList = nullList.orEmpty()
    println(emptyList)
    println(emptyList.size)

    val nonNullList: List<Int>? = listOf(1, 2, 3)
    val keptList = nonNullList.orEmpty()
    println(keptList)
    println(keptList.size)

    // String?.orEmpty()
    val nullStr: String? = null
    val emptyStr = nullStr.orEmpty()
    println("'$emptyStr'")
    println(emptyStr.length)

    val nonNullStr: String? = "hello"
    val keptStr = nonNullStr.orEmpty()
    println("'$keptStr'")
    println(keptStr.length)
}
