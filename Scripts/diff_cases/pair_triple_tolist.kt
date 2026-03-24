fun main() {
    val p = Pair(1, "hello")
    println(p.toList())
    println(p.first)
    println(p.second)
    val t = Triple(1, "hello", true)
    println(t.toList())
    println(t.first)
    println(t.second)
    println(t.third)
    val (a, b) = 1 to "one"
    println("$a $b")
}
