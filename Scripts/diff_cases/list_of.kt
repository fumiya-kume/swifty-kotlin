fun main() {
    val list = listOf(1, 2, 3)
    println(list)
    println(list.size)
    println(list[0])
    println(list.get(0))
    println(list.get(1))
    println(list.get(2))
    println(list.contains(2))
    println(list.contains(5))
    println(list.isEmpty())
    println(listOf<Int>())
    println(listOf("a", "b", "c").joinToString())
    for (x in listOf(10, 20, 30)) {
        println(x)
    }
}
