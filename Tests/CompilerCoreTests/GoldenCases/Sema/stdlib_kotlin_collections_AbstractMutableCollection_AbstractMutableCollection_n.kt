package golden.sema

class BagIterator(private val items: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < items.size

    override fun next(): Int = items[index++]

    override fun remove() {
        items.removeAt(--index)
    }
}

class Bag : AbstractMutableCollection<Int>() {
    private val items = ArrayList<Int>()

    override val size: Int
        get() = items.size

    override fun iterator(): MutableIterator<Int> = BagIterator(items)

    override fun add(element: Int): Boolean {
        items.add(element)
        return true
    }
}

fun probe(values: Bag): Int {
    var result = 0
    if (values.addAll(listOf(1, 2))) result += 1
    if (values.remove(1)) result += 2
    if (values.removeAll(listOf(2))) result += 4
    if (values.retainAll(listOf(3))) result += 8
    values.clear()
    return result + values.size
}
