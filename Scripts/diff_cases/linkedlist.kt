fun main() {
    val list = java.util.LinkedList<Int>()
    list.add(1)
    list.add(2)
    list.add(3)
    println(list)
    println(list.size)
    list.addFirst(0)
    list.addLast(4)
    println(list)
    println(list.first)
    println(list.last)
}
