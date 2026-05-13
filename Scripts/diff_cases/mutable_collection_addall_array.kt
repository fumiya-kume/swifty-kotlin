fun main() {
    val list = mutableListOf(1)
    println(list.addAll(arrayOf(2, 3)))
    println(list)
    println(list.addAll(emptyArray<Int>()))
    println(list)

    val set = mutableSetOf(1)
    println(set.addAll(arrayOf(1, 2, 2, 3)))
    println(set)
    println(set.addAll(arrayOf(1, 2, 3)))
    println(set)

    val collection: MutableCollection<Int> = mutableListOf(10)
    println(collection.addAll(arrayOf(11, 12)))
    println(collection)
}
