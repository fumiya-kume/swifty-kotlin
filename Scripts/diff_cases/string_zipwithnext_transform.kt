fun main() {
    val s = "abcde"

    println(s.zipWithNext())

    val pairs = s.zipWithNext { a, b -> "$a$b" }
    println(pairs)

    println("".zipWithNext { a, b -> "$a$b" })
    println("x".zipWithNext { a, b -> "$a$b" })
}
