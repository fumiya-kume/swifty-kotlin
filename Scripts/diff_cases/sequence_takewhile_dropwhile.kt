fun main() {
    println(sequenceOf(1, 2, 3, 4, 5).takeWhile { it < 4 }.toList())
    println(sequenceOf(1, 2, 3, 4, 5).dropWhile { it < 3 }.toList())
}
