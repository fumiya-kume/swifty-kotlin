fun classify(x: Int): String = when (x) {
    1, 2, 3 -> "few"
    else -> "many"
}

fun main() {
    println(classify(1))
    println(classify(2))
    println(classify(5))
}
