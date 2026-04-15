fun main() {
    val list = listOf(10, 20, 30, 40, 50)

    // elementAt — valid index
    println(list.elementAt(0))  // 10
    println(list.elementAt(2))  // 30
    println(list.elementAt(4))  // 50

    // elementAtOrNull — valid and out-of-bounds
    println(list.elementAtOrNull(1))   // 20
    println(list.elementAtOrNull(99))  // null

    // elementAtOrElse — valid and out-of-bounds
    println(list.elementAtOrElse(1) { it * 100 })   // 20
    println(list.elementAtOrElse(99) { it * 100 })  // 9900
}
