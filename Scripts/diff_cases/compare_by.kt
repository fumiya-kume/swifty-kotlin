fun main() {
    // sortedWith with lambda (Comparator via SAM)
    println(listOf(3, 1, 2).sortedWith { a, b -> b - a })
}
