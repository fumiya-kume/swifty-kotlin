fun main() {
    val windows = sequenceOf(1, 2, 3, 4, 5).windowed(3, 2, true).toList()
    println(windows)

    val empty = emptySequence<Int>().windowed(3, 1, true).toList()
    println(empty)
}
