fun main() {
    val left: Int? = 10
    val right = 20
    val missing: Int? = null

    println(left?.compareTo(right) ?: 0)
    println(left?.compareTo(right + 1) ?: -1)
    println(missing?.compareTo(right) ?: 1)

    fun <T> compareItems(items: List<T>, a: T, b: T) where T : Comparable<T> {
        println(items.size)
        println(a.compareTo(b))
        println(a < b)
        println(a > b)
    }

    compareItems(listOf(1, 2, 3), 10, 20)
    compareItems(listOf("a", "b", "c"), "apple", "banana")
}
