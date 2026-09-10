package golden.sema

fun main() {
    val empty = ArrayDeque<Int>()
    val copied = ArrayDeque<Int>(listOf(1, 2, 3))
    val sized = ArrayDeque<Int>(4)
    println(empty.size)
    println(copied.first())
    println(sized.size)
}
