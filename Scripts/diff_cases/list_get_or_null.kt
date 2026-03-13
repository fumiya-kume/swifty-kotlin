fun main() {
    val list = listOf(1, 2, 3)
    println(list.getOrNull(1))
    println(list.getOrNull(5))
    println(list.getOrElse(5) { -1 })
    println(list.elementAtOrNull(0))
    println(list.elementAtOrNull(10))
}
