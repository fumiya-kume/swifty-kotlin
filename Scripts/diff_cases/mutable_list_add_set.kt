fun main() {
    val list = mutableListOf(1, 3, 4)
    list.add(1, 2)
    println(list)

    val old = list.set(0, 10)
    println(old)
    println(list)

    list[2] = 30
    println(list)
}
