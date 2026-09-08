fun probeArrayList(input: Collection<Int>): Boolean {
    val empty: ArrayList<Int> = ArrayList()
    val capacity = ArrayList<Int>(4)
    val copied = ArrayList(input)
    val fromFactory: ArrayList<Int> = arrayListOf(1, 2)
    val mutable: MutableList<Int> = empty
    val readonly: List<Int> = empty
    mutable.add(3)
    return empty is ArrayList<*>
        && empty is MutableList<*>
        && empty is RandomAccess
        && capacity.size == 0
        && copied.size == input.size
        && fromFactory.size == 2
        && readonly.size == 1
}
