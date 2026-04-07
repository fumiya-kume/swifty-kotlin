fun main() {
    val s = "hello"
    println(s.getOrNull(0))   // h
    println(s.getOrNull(4))   // o
    println(s.getOrNull(5))   // null
    println(s.getOrNull(-1))  // null
}
