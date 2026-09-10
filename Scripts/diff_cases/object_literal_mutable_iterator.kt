// BUG-239: an object literal implementing an interface with no superclass
// (e.g. `object : MutableIterator<Int> { ... }`) previously left its itable
// slots empty, so every interface it registers (here both `Iterator` and
// `MutableIterator`) collided into slot 0 and the later registration
// silently overwrote the earlier interface's method table.
class Counter : MutableIterable<Int> {
    override fun iterator(): MutableIterator<Int> {
        return object : MutableIterator<Int> {
            var i = 0
            override fun hasNext() = i < 3
            override fun next(): Int {
                val v = i
                i++
                return v
            }

            override fun remove() {}
        }
    }
}

fun printAll(source: MutableIterable<Int>) {
    val iter = source.iterator()
    while (iter.hasNext()) {
        print(iter.next())
        print(" ")
    }
}

fun main() {
    printAll(Counter())
    printAll(mutableListOf(10, 20, 30))
}
