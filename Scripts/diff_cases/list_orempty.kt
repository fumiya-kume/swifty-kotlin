fun main() {
    // Non-null list
    val list: List<Int>? = listOf(1, 2, 3)
    println(list.orEmpty())

    // Null list
    val nullList: List<Int>? = null
    println(nullList.orEmpty())

    // Empty non-null list
    val emptyList: List<String>? = listOf()
    println(emptyList.orEmpty())

    // orEmpty on direct null literal
    println((null as List<Int>?).orEmpty())

    // Chain with size
    val items: List<String>? = listOf("a", "b")
    println(items.orEmpty().size)

    // Null chain with size
    val noItems: List<String>? = null
    println(noItems.orEmpty().size)
}
