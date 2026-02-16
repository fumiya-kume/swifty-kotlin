fun main() {
    val x = 3
    println(if (x != 2) 10 else 20)
    println(if (x < 5) 1 else 2)
    println(if (x <= 3) 3 else 4)
    println(if (x > 1) 5 else 6)
    println(if (x >= 3) 7 else 8)
    println(if (true && false) 9 else 10)
    println(if (false || true) 11 else 12)
}
