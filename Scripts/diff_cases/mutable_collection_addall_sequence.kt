fun addToCollection(values: MutableCollection<Int>, source: Sequence<Int>) {
    println(values.addAll(source))
    println(values)
}

fun addToList(values: MutableList<Int>, source: Sequence<Int>) {
    println(values.addAll(source))
    println(values)
}

fun addToSet(values: MutableSet<Int>, source: Sequence<Int>) {
    println(values.addAll(source))
    println(values)
}

fun main() {
    val collection: MutableCollection<Int> = mutableListOf(1)
    addToCollection(collection, sequenceOf(2, 3))

    val list = mutableListOf(1)
    addToList(list, sequenceOf(2, 3).map { it + 1 })

    val set = mutableSetOf(1)
    addToSet(set, sequenceOf(1, 2, 2, 3))
    addToSet(set, sequenceOf(1, 2, 3))
}
