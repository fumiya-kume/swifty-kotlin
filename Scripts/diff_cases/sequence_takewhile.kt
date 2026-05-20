fun main() {
    sequenceOf(1, 2, 3, 4, 2).takeWhile { value -> value < 4 }.forEach { value -> println(value) }
    sequenceOf(4, 1, 2).takeWhile { value -> value < 4 }.forEach { value -> println(value) }
    sequenceOf(1, 2, 3).takeWhile { value -> value < 10 }.forEach { value -> println(value) }
}
