package golden.sema

import kotlin.collections.AbstractMutableList

class Probe : AbstractMutableList<Int>() {
    override val size: Int
        get() = 0

    override fun get(index: Int): Int = 0

    override fun set(index: Int, element: Int): Int = 0

    override fun add(index: Int, element: Int) {}

    override fun removeAt(index: Int): Int = 0

    fun clearRange() {
        removeRange(0, size)
    }

    fun currentModifications(): Int = modCount
}

fun exercise(values: Probe) {
    values.add(1)
    values.add(0, 1)
    values.addAll(0, listOf(1))
    values.clear()
    values.contains(1)
    values.indexOf(1)
    values.lastIndexOf(1)
    values.iterator()
    values.listIterator()
    values.listIterator(0)
    values.removeAll(listOf(1))
    values.retainAll(listOf(1))
    values.subList(0, 0)
    values.equals(values)
    values.hashCode()
    values.clearRange()
    values.currentModifications()
}
