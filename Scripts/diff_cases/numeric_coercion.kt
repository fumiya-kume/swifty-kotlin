fun main() {
    println(15.coerceIn(1, 10))
    println(5.coerceIn(1, 10))
    println(0.coerceIn(1, 10))
    println(5.coerceAtLeast(10))
    println(15.coerceAtLeast(10))
    println(5.coerceAtMost(10))
    println(15.coerceAtMost(10))
}
