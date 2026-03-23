fun main() {
    val x = 42
    println("x = $x")
    println("x + 1 = ${x + 1}")
    println("length of hello = ${"hello".length}")
    val list = listOf(1, 2, 3)
    println("list = $list, size = ${list.size}")
    println("condition: ${if (x > 0) "positive" else "non-positive"}")
    println("\$literal dollar")
}
