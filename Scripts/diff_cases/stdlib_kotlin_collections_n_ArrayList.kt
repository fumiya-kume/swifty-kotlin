fun main() {
    val input: Collection<Int> = listOf(1, 2, 3)
    val empty = ArrayList<Int>()
    val capacity = ArrayList<Int>(4)
    val copied = ArrayList(input)
    val fromFactory = arrayListOf(4, 5)

    empty.add(0)
    val mutable: MutableList<Int> = empty
    mutable.add(6)

    println(empty.size)
    println(capacity.size)
    println(copied.size)
    println(fromFactory.size)
    println(empty is ArrayList<*>)
    println(empty is MutableList<*>)
    println(empty is RandomAccess)
}
