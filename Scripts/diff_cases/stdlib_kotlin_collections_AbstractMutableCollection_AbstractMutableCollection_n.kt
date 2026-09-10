// KSP-1034: AbstractMutableCollection supplies the standard bulk mutation
// implementations to subclasses that only provide add/size/iterator.

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

fun main() {
    val values = Bag()
    println(values.addAll(listOf(1, 2, 2, 3)))
    println(values.size)
    println(values.remove(2))
    println(values.remove(9))
    println(values.removeAll(listOf(2, 3)))
    println(values.size)
    println(values.removeAll(listOf(4)))
    values.addAll(listOf(1, 2, 3))
    println(values.retainAll(listOf(1, 3)))
    println(values.size)
    println(values.retainAll(listOf(1, 3)))
    values.clear()
    println(values.size)
}
