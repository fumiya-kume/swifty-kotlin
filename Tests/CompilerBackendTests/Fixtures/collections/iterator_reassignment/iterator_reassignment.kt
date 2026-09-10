class ThrowingIterator : Iterator<Int> {
    override fun hasNext(): Boolean = true
    override fun next(): Int = throw IllegalStateException("changed iterator")
}

fun main() {
    var iterator: Iterator<Int> = listOf(1, 2).iterator()
    println(iterator.next())
    val original = iterator
    iterator = ThrowingIterator()
    try {
        iterator.next()
    } catch (e: IllegalStateException) {
        println("caught")
    }
    println(original.next())
    iterator = listOf(3).iterator()
    println(iterator.next())
}
