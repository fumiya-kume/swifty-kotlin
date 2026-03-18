fun main() {
    val list = mutableListOf<Int>()
    list.add(1)
    list.add(2)
    list.add(3)
    println(list)
    println(list.size)
    list.add(0, 0)
    list.add(4)
    println(list)
    println(list.first())
    println(list.last())
}
