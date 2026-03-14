fun main() {
    val a = setOf(1, 2, 3, 4)
    val b = setOf(3, 4, 5, 6)
    val c = listOf(2, 4, 8)
    println(a.intersect(b))
    println(a.union(b))
    println(a.subtract(b))
    println(a.intersect(c))
    println(a.union(c))
    println(a.subtract(c))
}
