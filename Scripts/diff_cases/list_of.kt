fun main() {
    val list = listOf(1, 2, 3)
    println(list.size)
    println(list.get(0))
    println(list.get(1))
    println(list.get(2))
    println(list.contains(2))
    println(list.contains(5))
    println(list.isEmpty())
    for (x in listOf(10, 20, 30)) {
        println(x)
    }
}
