fun main() {
    val copied = ArrayDeque(listOf(1, 2, 3))
    println(copied.size)
    println(copied.first())
    println(copied.last())

    val sized = ArrayDeque<Int>(4)
    sized.addLast(9)
    println(sized.size)
    println(sized.first())

    try {
        ArrayDeque<Int>(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
