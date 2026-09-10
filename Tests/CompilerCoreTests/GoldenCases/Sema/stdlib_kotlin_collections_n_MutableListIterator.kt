package golden.sema

class CustomMutableListIterator : MutableListIterator<Int> {
    override fun hasNext(): Boolean = false
    override fun next(): Int = 0
    override fun hasPrevious(): Boolean = false
    override fun previous(): Int = 0
    override fun nextIndex(): Int = 0
    override fun previousIndex(): Int = 0
    override fun add(element: Int) {}
    override fun set(element: Int) {}
    override fun remove() {}
}

fun acceptListIterator(value: ListIterator<Int>) {}
fun acceptMutableIterator(value: MutableIterator<Int>) {}
fun acceptMutableListIterator(value: MutableListIterator<Int>) {}

fun probe(iterator: MutableListIterator<Int>) {
    acceptListIterator(iterator)
    acceptMutableIterator(iterator)
    acceptMutableListIterator(iterator)
    iterator.add(1)
    iterator.set(2)
    iterator.remove()
    iterator.hasNext()
    iterator.next()
    iterator.hasPrevious()
    iterator.previous()
}
