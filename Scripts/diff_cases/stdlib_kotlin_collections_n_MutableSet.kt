fun acceptSet(values: Set<Int>): Boolean = values.contains(4) && values.size == 3

fun acceptMutableCollection(values: MutableCollection<Int>): Boolean {
    val added = values.add(6)
    val removed = values.remove(3)
    return added && removed
}

fun iteration(values: MutableSet<Int>): String {
    val result = mutableListOf<Int>()
    for (element in values) {
        result.add(element)
    }
    return result.toString()
}

fun main() {
    val values: MutableSet<Int> = mutableSetOf(1, 2, 2, 3)
    println(values.add(3))
    println(values.add(4))
    println(values.remove(9))
    println(values.remove(1))
    println(values.addAll(listOf(4, 5)))
    println(values.removeAll(setOf(2, 9)))
    println(values.retainAll(listOf(3, 4, 5)))
    values += 6
    values -= 6
    values += listOf(6)
    values -= listOf(6)
    println(values)
    println(iteration(values))

    val readonly: Set<Int> = values
    println(acceptSet(readonly))

    val mutable: MutableCollection<Int> = values
    println(acceptMutableCollection(mutable))
    println(values)
    println(values == setOf(6, 5, 4))
    println(values.hashCode() == setOf(6, 5, 4).hashCode())

    mutable.clear()
    println(values)
}
