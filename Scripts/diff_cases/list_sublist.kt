fun main() {
    val list = listOf(1, 2, 3, 4, 5)

    // Basic subList
    println(list.subList(1, 3))
    println(list.subList(0, 5))
    println(list.subList(2, 2))
    println(list.subList(0, 0))
    println(list.subList(0, 1))
    println(list.subList(4, 5))

    // subList with strings
    val strings = listOf("a", "b", "c", "d")
    println(strings.subList(1, 3))
    println(strings.subList(0, 4))

    // subList size and element access
    val sub = list.subList(1, 4)
    println(sub.size)
    println(sub[0])
    println(sub[1])
    println(sub[2])

    // subList contains
    println(sub.contains(2))
    println(sub.contains(5))

    // subList indexOf
    println(sub.indexOf(3))
    println(sub.indexOf(5))

    // subList isEmpty
    println(list.subList(2, 2).isEmpty())
    println(list.subList(1, 3).isEmpty())

    // MutableList subList
    val mutable = mutableListOf(10, 20, 30, 40, 50)
    val mutableSub = mutable.subList(1, 4)
    println(mutableSub)
    mutableSub[0] = 99
    println(mutableSub)
    println(mutable)

    // subList iteration
    for (item in list.subList(2, 5)) {
        println(item)
    }
}
