fun main() {
    println(sequenceOf(3, 1, 2, 1).sortedWith { a, b -> a - b }.toList())
    println(sequenceOf(3, 1, 2, 1).sortedWith { a, b -> b - a }.toList())
}
