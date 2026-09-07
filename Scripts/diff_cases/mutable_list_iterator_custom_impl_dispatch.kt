private class ProbeMutableListIterator : MutableListIterator<Int> {
    override fun hasNext(): Boolean {
        print("[hasNext]")
        return true
    }

    override fun next(): Int {
        print("[next]")
        return 111
    }

    override fun hasPrevious(): Boolean {
        print("[hasPrevious]")
        return true
    }

    override fun previous(): Int {
        print("[previous]")
        return 222
    }

    override fun nextIndex(): Int {
        print("[nextIndex]")
        return 333
    }

    override fun previousIndex(): Int {
        print("[previousIndex]")
        return 444
    }

    override fun add(element: Int) {
        print("[add:$element]")
    }

    override fun set(element: Int) {
        print("[set:$element]")
    }

    override fun remove() {
        print("[remove]")
    }
}

fun main() {
    val viaMutable: MutableListIterator<Int> = ProbeMutableListIterator()
    print("hasPrevious=${viaMutable.hasPrevious()} ")
    print("previous=${viaMutable.previous()} ")
    print("nextIndex=${viaMutable.nextIndex()} ")
    print("previousIndex=${viaMutable.previousIndex()} ")
    viaMutable.add(9)
    viaMutable.set(8)
    viaMutable.remove()
    println()

    val list = mutableListOf(1, 2, 3)
    val it = list.listIterator()
    it.next()
    it.set(10)
    print("afterSet=$list ")
    it.add(20)
    print("afterAdd=$list ")

    val it2 = list.listIterator()
    it2.next()
    it2.remove()
    print("afterRemove=$list")
}
