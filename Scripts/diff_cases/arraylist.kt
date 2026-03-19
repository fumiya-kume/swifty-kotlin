fun main() {
    val list = ArrayList<Int>()
    list.add(1)
    list.add(2)
    list.add(3)
    println(list)
    println(list.size)
    list.removeAt(1)
    println(list)
    list.add(0, 10)
    println(list)
}
