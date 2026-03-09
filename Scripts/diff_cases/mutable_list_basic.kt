fun main() {
    val list = mutableListOf(1, 2)
    list.add(3)
    println(list)

    val removed = list.removeAt(1)
    println(removed)
    println(list)

    list.clear()
    println(list)
}
