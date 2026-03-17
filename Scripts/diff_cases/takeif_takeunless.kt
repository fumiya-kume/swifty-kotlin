fun main() {
    val x = 42
    println(x.takeIf { it > 0 })
    println(x.takeIf { it > 100 })
    println(x.takeUnless { it > 100 })
    println(x.takeUnless { it > 0 })
    val s = "hello"
    println(s.takeIf { it.length > 3 })
    println(s.takeUnless { it.isEmpty() })
}
