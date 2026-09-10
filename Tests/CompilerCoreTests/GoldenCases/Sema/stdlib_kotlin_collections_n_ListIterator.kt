private class ProbeListIterator : ListIterator<Int> {
    private var cursor = 0

    override fun hasNext(): Boolean = cursor < 2
    override fun next(): Int {
        val value = cursor + 10
        cursor += 1
        return value
    }
    override fun hasPrevious(): Boolean = cursor > 0
    override fun previous(): Int {
        cursor -= 1
        return cursor + 10
    }
    override fun nextIndex(): Int = cursor
    override fun previousIndex(): Int = cursor - 1
}

fun inspect(iterator: ListIterator<Int>): Int {
    val next = if (iterator.hasNext()) iterator.next() else iterator.previous()
    return next + iterator.nextIndex() + iterator.previousIndex()
}

fun main() {
    val iterator: ListIterator<Int> = listOf(10, 20, 30).listIterator()
    inspect(iterator)
    inspect(ProbeListIterator())
}
