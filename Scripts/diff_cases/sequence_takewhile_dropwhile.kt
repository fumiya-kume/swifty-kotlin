fun main() {
    sequenceOf(1, 2, 3, 4, 5).takeWhile { it < 4 }.forEach { println(it) }
    sequenceOf(1, 2, 3, 4, 5).dropWhile { it < 3 }.forEach { println(it) }
}
