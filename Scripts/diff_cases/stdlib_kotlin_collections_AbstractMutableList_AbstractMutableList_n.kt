class Probe : AbstractMutableList<Int>() {
    private val items = intArrayOf(1, 2, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0)
    private var itemCount = 4

    override val size: Int
        get() = itemCount

    override fun get(index: Int): Int = items[index]

    override fun set(index: Int, element: Int): Int {
        val previous = items[index]
        items[index] = element
        return previous
    }

    override fun add(index: Int, element: Int) {
        var cursor = itemCount
        while (cursor > index) {
            items[cursor] = items[cursor - 1]
            cursor -= 1
        }
        items[index] = element
        itemCount += 1
        modCount += 1
    }

    override fun removeAt(index: Int): Int {
        val result = items[index]
        var cursor = index
        while (cursor + 1 < itemCount) {
            items[cursor] = items[cursor + 1]
            cursor += 1
        }
        itemCount -= 1
        modCount += 1
        return result
    }
}

private fun render(values: Probe): String {
    var result = ""
    var index = 0
    while (index < values.size) {
        if (index > 0) result += ","
        result += values.get(index)
        index += 1
    }
    return result
}

fun main() {
    val values = Probe()
    println(values.add(4))
    println(values.addAll(1, listOf(8, 9)))
    println(values.addAll(0, emptyList()))
    println(values.contains(2))
    println(values.indexOf(2))
    println(values.lastIndexOf(2))

    val listIterator = values.listIterator(2)
    println(listIterator.previous())
    println(listIterator.next())
    values.set(2, 7)
    println(render(values))

    val iterator = values.iterator()
    while (iterator.hasNext()) {
        if (iterator.next() == 7) iterator.remove()
    }
    println(render(values))

    values.subList(1, 4)

    val expected = Probe()
    expected.clear()
    expected.add(1)
    expected.add(8)
    expected.add(2)
    expected.add(2)
    expected.add(3)
    expected.add(4)
    println(values == values)
    println(values.hashCode() == expected.hashCode())

    println(values.removeAll(listOf(2)))
    println(render(values))
    println(values.retainAll(listOf(1, 3)))
    println(render(values))
    values.clear()
    println(values.isEmpty())
}
