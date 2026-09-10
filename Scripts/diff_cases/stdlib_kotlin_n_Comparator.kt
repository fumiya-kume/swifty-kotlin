class ReverseComparator : Comparator<Int> {
    override fun compare(a: Int, b: Int): Int = b - a
}

fun main() {
    val cmp = Comparator<Int> { a, b -> a.compareTo(b) }
    println(cmp.compare(3, 5))
    println(cmp.compare(7, 2))
    println(cmp.compare(4, 4))

    val explicit: Comparator<Int> = ReverseComparator()
    println(explicit.compare(3, 5))
    println(listOf(3, 1, 2).sortedWith(explicit))
}
