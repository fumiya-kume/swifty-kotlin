fun classify(x: Int): String = when {
    x < 0 -> "negative"
    x == 0 -> "zero"
    x < 10 -> "small"
    x < 100 -> "medium"
    else -> "large"
}
fun main() {
    println(classify(-5))
    println(classify(0))
    println(classify(7))
    println(classify(42))
    println(classify(999))
}
